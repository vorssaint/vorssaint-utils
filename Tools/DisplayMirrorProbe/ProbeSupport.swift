// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case let .message(message): return message } }
}

struct ProbeOptions: Sendable {
    enum Mode: String, Sendable { case flipped, plain, capture }
    var displayID: UInt32?
    var fps = 60
    var seconds = 60
    var width: Int?
    var mode = Mode.flipped
    var list = false
    var selftest = false
    var help = false

    static let usage = """
    Display Mirror Probe (experimental, macOS 14+, Apple Silicon)
      --list                       List connected displays; does not capture.
      --selftest                   Test options and the Metal shader offscreen.
      --display ID                 External display to capture and overlay.
      --fps 30|60                  Maximum capture rate (default 60).
      --width 1920|3840            Capture width; default is native pixels.
      --seconds 10...600           Automatic stop (default 60 seconds).
      --mode flipped|plain|capture Compare flip, unflipped render, capture only.

    Run the bundle executable from Terminal to see CSV measurements. Ctrl-C or
    the Mirror Probe menu's Stop item ends the experiment. The native pointer
    is left unchanged: cursor mirroring is NOT implemented in this probe.
    """

    static func parse(_ args: [String]) throws -> Self {
        var options = Self()
        var index = 0
        var seen = Set<String>()
        while index < args.count {
            let key = args[index]
            guard seen.insert(key).inserted else { throw ProbeError.message("Duplicate option: \(key)") }
            index += 1
            if key == "--list" { options.list = true; continue }
            if key == "--selftest" { options.selftest = true; continue }
            if key == "--help" { options.help = true; continue }
            guard ["--display", "--fps", "--width", "--seconds", "--mode"].contains(key),
                  index < args.count else { throw ProbeError.message("Unknown or incomplete option: \(key)") }
            let value = args[index]
            index += 1
            switch key {
            case "--display":
                guard let id = UInt32(value), id != 0 else { throw ProbeError.message("Invalid display ID") }
                options.displayID = id
            case "--fps":
                guard let fps = Int(value), [30, 60].contains(fps) else { throw ProbeError.message("Use 30 or 60 fps") }
                options.fps = fps
            case "--width":
                guard let width = Int(value), [1920, 3840].contains(width) else { throw ProbeError.message("Use width 1920 or 3840") }
                options.width = width
            case "--seconds":
                guard let seconds = Int(value), (10...600).contains(seconds) else { throw ProbeError.message("Use 10...600 seconds") }
                options.seconds = seconds
            case "--mode":
                guard let mode = Mode(rawValue: value) else { throw ProbeError.message("Unknown mode: \(value)") }
                options.mode = mode
            default: break
            }
        }
        guard options.help || options.list || options.selftest || options.displayID != nil else {
            throw ProbeError.message("Choose an external display with --display ID; use --list first")
        }
        return options
    }
}

/// Bounded aggregates only; no frame pixels or unbounded per-frame history.
final class ProbeMetrics: @unchecked Sendable {
    struct Snapshot {
        var complete = 0
        var skipped = 0
        var submitted = 0
        var finished = 0
        var gpuMilliseconds = 0.0
        var callbackToSubmitMilliseconds = 0.0
    }
    private let lock = NSLock()
    private var value = Snapshot()
    func complete() { lock.withLock { value.complete += 1 } }
    func skip() { lock.withLock { value.skipped += 1 } }
    func submit(delay: Double) {
        lock.withLock {
            value.submitted += 1
            value.callbackToSubmitMilliseconds += delay * 1000
        }
    }
    func finish(gpuSeconds: Double) {
        lock.withLock {
            value.finished += 1
            value.gpuMilliseconds += max(0, gpuSeconds) * 1000
        }
    }
    func snapshot() -> Snapshot { lock.withLock { value } }
}
