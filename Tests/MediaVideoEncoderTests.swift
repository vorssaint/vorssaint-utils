// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MediaVideoEncoderTests {
    static func run(_ suite: TestSuite) {
        presets(suite)
        arguments(suite)
        process(suite)
    }

    /// The table MediaService used before the preset choice moved out, so the
    /// Media workspace keeps producing exactly the same files.
    static func presets(_ suite: TestSuite) {
        func check(_ codec: MediaVideoCodec, _ maxDimension: Int, _ quality: Double, _ expected: String) {
            let actual = MediaVideoEncoder.avconvertPreset(codec: codec, maxDimension: maxDimension, quality: quality)
            suite.expect(actual == expected,
                         "preset \(codec) \(maxDimension) \(quality): expected \(expected), got \(actual)")
        }
        check(.h264, 1920, 0.2, "PresetLowQuality")
        check(.hevc, 1920, 0.39, "PresetLowQuality")
        check(.hevc, 1920, 0.9, "PresetHEVCHighestQuality")
        check(.hevc, 1920, 0.6, "PresetHEVC1920x1080")
        check(.hevc, 3840, 0.6, "PresetHEVC3840x2160")
        check(.hevc, 5000, 0.6, "PresetHEVCHighestQuality")
        check(.h264, 1920, 0.82, "PresetHighestQuality")
        check(.h264, 1920, 0.5, "PresetMediumQuality")
        check(.h264, 640, 0.7, "Preset640x480")
        check(.h264, 960, 0.7, "Preset960x540")
        check(.h264, 1280, 0.7, "Preset1280x720")
        check(.h264, 1920, 0.7, "Preset1920x1080")
        check(.h264, 3840, 0.7, "PresetHighestQuality")
        check(.h264, 1920, .nan, "Preset1920x1080")
    }

    static func arguments(_ suite: TestSuite) {
        let input = URL(fileURLWithPath: "/tmp/in put.mov")
        let output = URL(fileURLWithPath: "/tmp/out.mp4")
        let trimmed = MediaVideoEncoder.avconvertArguments(
            input: input, output: output, preset: "PresetHEVC1920x1080",
            trim: MediaTrimRange(start: 1.5, end: 3.25), multiPass: true)
        suite.expect(trimmed == [
            "--source", "/tmp/in put.mov", "--preset", "PresetHEVC1920x1080", "--output", "/tmp/out.mp4",
            "--replace", "--progress", "--start", "1.500", "--duration", "1.750", "--multiPass",
        ], "avconvert gets a trim with a decimal point and multi pass last: \(trimmed)")
        let whole = MediaVideoEncoder.avconvertArguments(
            input: input, output: output, preset: "PresetHighestQuality", trim: nil, multiPass: false)
        suite.expect(whole == [
            "--source", "/tmp/in put.mov", "--preset", "PresetHighestQuality", "--output", "/tmp/out.mp4",
            "--replace", "--progress",
        ], "a whole-file conversion passes no trim: \(whole)")
        suite.expect(MediaVideoEncoder.wantsMultiPass(quality: 0.82), "high quality uses multi pass")
        suite.expect(!MediaVideoEncoder.wantsMultiPass(quality: 0.81), "lower quality is a single pass")
    }

    /// The runner is driven with a stand-in executable, so cancellation and
    /// failure reporting are checked without encoding a video.
    static func process(_ suite: TestSuite) {
        let started = Date()
        var cancelled = false
        do {
            try MediaVideoEncoder.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                                      launch: { try $0.run() },
                                      isCancelled: { Date().timeIntervalSince(started) > 0.3 },
                                      tick: {})
        } catch MediaVideoEncoder.RunError.cancelled {
            cancelled = true
        } catch {
            suite.expect(false, "cancel threw \(error)")
        }
        suite.expect(cancelled, "a cancelled run throws cancelled")
        suite.expect(Date().timeIntervalSince(started) < 5, "a cancelled run stops the process promptly")

        var message: String?
        do {
            try MediaVideoEncoder.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                      arguments: ["-c", "echo broken >&2; exit 3"],
                                      launch: { try $0.run() }, isCancelled: { false }, tick: {})
        } catch MediaVideoEncoder.RunError.failed(let text) {
            message = text
        } catch {
            suite.expect(false, "failure threw \(error)")
        }
        suite.expect(message == "broken", "a failed run reports its output: \(message ?? "nil")")

        var ok = false
        do {
            try MediaVideoEncoder.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [],
                                      launch: { try $0.run() }, isCancelled: { false }, tick: {})
            ok = true
        } catch {
            suite.expect(false, "success threw \(error)")
        }
        suite.expect(ok, "a clean exit returns normally")
    }
}
