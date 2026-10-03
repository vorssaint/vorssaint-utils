// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Stateless `avconvert` helpers shared by the Media workspace and the
/// clipboard optimizer. The caller owns the queue it blocks and decides what
/// cancellation means; nothing here publishes progress or keeps state.
enum MediaVideoEncoder {
    enum RunError: Error, Equatable {
        case cancelled
        case failed(String)
    }

    static let avconvertURL = URL(fileURLWithPath: "/usr/bin/avconvert")

    static func avconvertPreset(codec: MediaVideoCodec, maxDimension: Int, quality: Double) -> String {
        let quality = MediaSupport.sanitizedQuality(quality)
        if quality < 0.4 {
            return "PresetLowQuality"
        }
        if codec == .hevc {
            if quality >= 0.82 { return "PresetHEVCHighestQuality" }
            if maxDimension <= 1920 { return "PresetHEVC1920x1080" }
            if maxDimension <= 3840 { return "PresetHEVC3840x2160" }
            return "PresetHEVCHighestQuality"
        }
        if quality >= 0.82 { return "PresetHighestQuality" }
        if quality < 0.58 { return "PresetMediumQuality" }
        if maxDimension <= 640 { return "Preset640x480" }
        if maxDimension <= 960 { return "Preset960x540" }
        if maxDimension <= 1280 { return "Preset1280x720" }
        if maxDimension <= 1920 { return "Preset1920x1080" }
        return "PresetHighestQuality"
    }

    static func wantsMultiPass(quality: Double) -> Bool {
        quality >= 0.82
    }

    static func avconvertArguments(input: URL, output: URL, preset: String,
                                   trim: MediaTrimRange?, multiPass: Bool) -> [String] {
        var arguments = [
            "--source", input.path,
            "--preset", preset,
            "--output", output.path,
            "--replace",
            "--progress",
        ]
        if let trim {
            // Deliberately not the reader's region: these are arguments for
            // a tool that reads a decimal point, and a comma would break the
            // trim in every country that writes numbers that way.
            let posix = Locale(identifier: "en_US_POSIX")
            arguments += [
                "--start", String(format: "%.3f", locale: posix, trim.start),
                "--duration", String(format: "%.3f", locale: posix, trim.duration),
            ]
        }
        if multiPass {
            arguments.append("--multiPass")
        }
        return arguments
    }

    /// Runs the tool on the caller's queue until it exits. `launch` starts the
    /// process, so a caller can make launch and cancellation atomic with its
    /// own bookkeeping. A cancelled run is terminated, then killed if it does
    /// not exit, and always reaped before this returns.
    static func run(executable: URL = avconvertURL,
                    arguments: [String],
                    launch: (Process) throws -> Void,
                    isCancelled: () -> Bool,
                    tick: () -> Void) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var log = ""
        let logLock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            logLock.lock()
            log.append(chunk)
            if log.count > 8_000 { log.removeFirst(log.count - 8_000) }
            logLock.unlock()
        }
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            stop(process)
        }
        try launch(process)
        while process.isRunning {
            if isCancelled() { throw RunError.cancelled }
            tick()
            Thread.sleep(forTimeInterval: 0.08)
        }
        if isCancelled() { throw RunError.cancelled }
        guard process.terminationStatus == 0 else {
            // Output still in the pipe when the process exits is read here.
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            logLock.lock()
            if let chunk = String(data: rest, encoding: .utf8) { log.append(chunk) }
            let message = log.trimmingCharacters(in: .whitespacesAndNewlines)
            logLock.unlock()
            throw RunError.failed(message)
        }
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}
