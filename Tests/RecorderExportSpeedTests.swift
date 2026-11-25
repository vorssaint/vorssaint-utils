// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure timing/document checks. Actual AVFoundation exports still need the
/// macOS smoke checks described in docs/recorder-export-speed.md.
enum RecorderExportSpeedTests {
    static func run(_ suite: TestSuite) {
        compression(suite)
        let original = RecorderEditDocument()
        suite.expect(original.exportSpeed == 1
                && original.exportDuration(duration: 10) == 10,
                     "new recordings retain normal export speed")
        let legacy = RecorderEditDocument.decoded(Data(
            #"{"trimStart":2,"trimEnd":12,"keepsSystemAudio":false}"#.utf8))
        suite.expect(legacy.exportSpeed == 1 && legacy.trimStart == 2
                && legacy.trimEnd == 12 && !legacy.keepsSystemAudio,
                     "older edit documents retain their edits and default to 1x")

        let custom = RecorderEditDocument(trimStart: 2, trimEnd: 12,
                                          exportSpeed: 1.37,
                                          keepsSystemAudio: false,
                                          cuts: [.init(start: 4, end: 6)],
                                          microphoneGain: 0.5)
        suite.expect(RecorderEditDocument.decoded(custom.encoded()) == custom,
                     "custom speeds round-trip with cuts and audio settings")
        suite.expect(RecorderExportTiming.presets.contains(1)
                && RecorderExportTiming.presets.contains(1.25)
                && RecorderExportTiming.presets.contains(1.5)
                && RecorderExportTiming.presets.contains(2)
                && RecorderExportTiming.presets.allSatisfy {
                    RecorderExportTiming.speedRange.contains($0)
                }, "the requested speeds and safe preset bounds are available")
        suite.expect(RecorderExportTiming(speed: 1.37).speed == 1.37,
                     "custom speeds are not snapped to presets")
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            suite.expect(RecorderExportTiming(speed: invalid).speed == 1,
                         "invalid export speeds fall back to normal speed")
            suite.expect(RecorderEditDocument(exportSpeed: invalid)
                .sanitized(duration: 10).exportSpeed == 1,
                         "document sanitization removes invalid export speeds")
        }
        suite.expect(RecorderExportTiming(speed: 0.01).speed == 0.25
                && RecorderExportTiming(speed: 100).speed == 4,
                     "positive out-of-range speeds are bounded")
        suite.expect(RecorderExportTiming(speed: 1.25)
                .outputTime(forSourceTime: 10) == 8,
                     "1.25x turns ten edited seconds into eight export seconds")
        suite.expect(RecorderExportTiming(speed: 0.25)
                .outputTime(forSourceTime: 10) == 40,
                     "slow motion increases duration instead of dropping time")
        for speed in [0.25, 0.5, 0.75, 1, 1.25, 1.37, 1.5, 2, 3, 4] {
            let timing = RecorderExportTiming(speed: speed)
            for seconds in [0.0, 0.001, 0.8, 1, 12.345, 3_600] {
                let exported = timing.outputTime(forSourceTime: seconds)
                suite.expect(abs(timing.sourceTime(forOutputTime: exported) - seconds) < 0.000001,
                             "the render clock reverses export scaling at every supported speed")
            }
        }

        var accelerated = custom
        accelerated.exportSpeed = 1.25
        suite.expect(accelerated.outputDuration(duration: 20) == 8
                && abs(accelerated.exportDuration(duration: 20) - 6.4) < 0.000001,
                     "speed is applied after trimming and cuts, not before")
        suite.expect(accelerated.keptRanges(duration: 20) == [2.0...4.0, 6.0...12.0],
                     "export speed never rewrites the source ranges")
        let sourceAfterCut = RecorderTimeline.sourceTime(
            forOutput: accelerated.exportTiming.sourceTime(forOutputTime: 2.4),
            trim: accelerated.trim(duration: 20), cuts: accelerated.cuts)
        suite.expect(abs(sourceAfterCut - 7) < 0.000001,
                     "overlay lookup maps the export clock back across a cut")
        var slowed = accelerated
        slowed.exportSpeed = 0.5
        suite.expect(slowed.outputDuration(duration: 20) == 8
                && slowed.exportDuration(duration: 20) == 16,
                     "preview duration is unchanged even when the export is slowed")
        suite.expect(!accelerated.affectsTiming(slowed)
                && !accelerated.affectsPicture(slowed)
                && !accelerated.affectsAudio(slowed),
                     "export-only changes do not rebuild preview timing, picture or audio")
        suite.expect(accelerated != slowed,
                     "undo and persistence still see an export-only document change")
        suite.expect(!original.isEdited(duration: 10)
                && RecorderEditDocument(exportSpeed: 1.25).isEdited(duration: 10),
                     "changing only export speed counts as an edit")
        suite.expect(custom.applying(.studio).exportSpeed == 1.37,
                     "visual looks leave the recording's export speed alone")
        suite.expect(RecorderEditPreset(name: "Look", document: original)
                .applying(to: custom).exportSpeed == 1.37,
                     "visual presets do not reset the recording's export speed")

        let fasterGIF = RecorderEditDocument(exportSpeed: 2)
        let slowerGIF = RecorderEditDocument(exportSpeed: 0.5)
        suite.expect(RecorderSupport.gifFrameCount(
            duration: fasterGIF.exportDuration(duration: 30), fps: 12) == 180,
                     "GIF sampling uses the accelerated output duration")
        suite.expect(RecorderSupport.gifFrameCount(
            duration: slowerGIF.exportDuration(duration: 20), fps: 12) == 480,
                     "slow GIFs retain every frame beyond the former frame budget")
        suite.expect(RecorderSupport.gifFrameCount(
            duration: fasterGIF.exportDuration(duration: 10), fps: 12) == 60,
                     "GIF sampling retains the chosen frame rate on the scaled timeline")
        suite.expect(RecorderEditDocument(exportSpeed: 4, cuts: [.init(start: 0, end: 10)])
                .exportDuration(duration: 10) == 0,
                     "an entirely cut recording stays empty at any speed")
    }
    private static func compression(_ suite: TestSuite) {
        let legacy = RecorderEditDocument.decoded(Data(#"{"quality":"balanced"}"#.utf8))
        suite.expect(legacy.exportMaxDimension == 0 && legacy.exportTargetBytes == 0,
                     "old recordings keep unrestricted exports")
        let source = CGSize(width: 3840, height: 2160)
        let document = RecorderEditDocument(trimStart: 2, trimEnd: 14, exportSpeed: 2,
            exportMaxDimension: 1280, cuts: [.init(start: 4, end: 6)])
        let plan = document.videoExportPlan(source: source, frameRate: 60, duration: 20, hasAudio: true)!
        suite.expect(plan.size == CGSize(width: 1280, height: 720) && plan.duration == 5,
                     "resolution and size estimate use the trimmed, cut and accelerated export")
        let smallQuality = RecorderEditDocument(quality: "small", exportMaxDimension: 1280)
        suite.expect(smallQuality.exportResolution(source: source) == CGSize(width: 1280, height: 720),
                     "an explicit resolution overrides preset scaling while retaining its bitrate quality")
        var decorated = document
        decorated.blurs = [.init(start: 0, end: 20)]
        let composer = RecorderComposer.makePlan(document: decorated, track: RecorderPointerTrack(),
            sourceSize: source, frameRate: 60, duration: 20, outputSize: CGSize(width: 64, height: 36))
        suite.expect(composer?.canvasSize == CGSize(width: 64, height: 36),
                     "effects render at the exact planned resolution, including reductions below ten percent")
        let silent = document.videoExportPlan(source: source, frameRate: 60, duration: 20, hasAudio: false)!
        suite.expect(plan.estimatedBytes > silent.estimatedBytes,
                     "file-size estimates include retained audio")
        let original = legacy.videoExportPlan(source: source, frameRate: 60, duration: 20, hasAudio: true)!
        suite.expect(plan.estimatedBytes < original.estimatedBytes,
                     "lowering resolution and duration reduces the visible size estimate")
        let smallSource = document.videoExportPlan(source: CGSize(width: 320, height: 180),
            frameRate: 30, duration: 20, hasAudio: false)!
        suite.expect(smallSource.size == CGSize(width: 320, height: 180),
                     "a resolution limit does not upscale a small recording")
        var targeted = document
        targeted.exportTargetMegabytes = 1
        let target = targeted.videoExportPlan(source: source, frameRate: 60, duration: 20, hasAudio: true)!
        suite.expect(target.estimatedBytes <= targeted.exportTargetBytes
                && target.size.width <= 1280 && target.size.height <= 720,
                     "the budget reserves audio and container space within the selected resolution")
        suite.expect(RecorderEditDocument(exportTargetMegabytes: 1).videoExportPlan(
            source: source, frameRate: 60, duration: 3600, hasAudio: true) == nil,
                     "an unreachable limit is refused before encoding")
        suite.expect(RecorderEditDocument.decoded(targeted.encoded()) == targeted,
                     "export size and resolution survive reopening the recording")
        let sanitized = RecorderEditDocument(exportMaxDimension: -1, exportTargetMegabytes: 1000)
            .sanitized(duration: 20)
        suite.expect(sanitized.exportMaxDimension == 0 && sanitized.exportTargetMegabytes == 512,
                     "damaged export settings are bounded")
        suite.expect(!document.affectsPicture(targeted) && !document.affectsTiming(targeted)
                && !document.affectsAudio(targeted), "compression changes leave the editing preview alone")
        suite.expect(RecorderEditDocument(exportMaxDimension: 1280).isEdited(duration: 20)
                && RecorderEditDocument(exportTargetMegabytes: 20).isEdited(duration: 20),
                     "export-only settings count as changes before closing")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.recorderCompression(language)
            suite.expect(!strings.originalResolution.isEmpty && !strings.limitFileSize.isEmpty
                    && !strings.estimateHint.isEmpty, "compression controls are translated for \(language)")
        }
    }
}
