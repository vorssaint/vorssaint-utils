// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

enum FFmpeg {
    /// A copy shipped inside the app comes first, so conversions work offline
    /// on any Mac; then a path set in settings; then one on the system.
    private static func bundled(_ name: String) -> String? {
        guard let path = Bundle.main.resourceURL?.appendingPathComponent("bin/\(name)").path,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    static var path: String? {
        if let bundled = bundled("ffmpeg") { return bundled }
        let configured = AppSettings.shared.ffmpegPath.trimmingCharacters(in: .whitespaces)
        if !configured.isEmpty, FileManager.default.isExecutableFile(atPath: configured) { return configured }
        return ConvertShell.which("ffmpeg")
    }

    static var probePath: String? {
        if let bundled = bundled("ffprobe") { return bundled }
        if let ffmpeg = path {
            let sibling = (ffmpeg as NSString).deletingLastPathComponent + "/ffprobe"
            if FileManager.default.isExecutableFile(atPath: sibling) { return sibling }
        }
        return ConvertShell.which("ffprobe")
    }

    static var isAvailable: Bool { path != nil }

    enum Health: Equatable {
        case missing
        case broken(path: String, reason: String)
        case ready(path: String, version: String)
    }

    static func checkHealth() async -> Health {
        guard let ffmpeg = path else { return .missing }
        do {
            let result = try await ConvertShell.run(ffmpeg, ["-hide_banner", "-version"])
            let firstLine = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
            guard result.succeeded, firstLine.hasPrefix("ffmpeg version") else {
                return .broken(path: ffmpeg, reason: summarize(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
            let version = firstLine.replacingOccurrences(of: "ffmpeg version ", with: "")
                .split(separator: " ").first.map(String.init) ?? ""
            return .ready(path: ffmpeg, version: version)
        } catch {
            return .broken(path: ffmpeg, reason: error.localizedDescription)
        }
    }

    static func availableEncoders() async -> Set<String> {
        guard let executable = path,
              let result = try? await ConvertShell.run(executable, ["-hide_banner", "-encoders"]), result.succeeded else { return [] }
        return Set(result.stdout.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2, fields[0].count == 6,
                  ["V", "A", "S"].contains(String(fields[0].prefix(1))), fields[1] != "=" else { return nil }
            return String(fields[1])
        })
    }

    static func summarize(_ output: String) -> String {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let dyld = lines.first(where: { $0.contains("Library not loaded") }) {
            let library = dyld.components(separatedBy: "Library not loaded: ").last.map { ($0 as NSString).lastPathComponent } ?? ""
            return "missing library \(library). Reinstall ffmpeg and its dependencies (for example `brew reinstall ffmpeg`)."
        }
        if let cause = lines.first(where: { $0.contains("Unknown encoder") || $0.contains("Encoder not found") || $0.contains("Invalid data found") || $0.contains("Permission denied") }) { return cause }
        return lines.last(where: { !$0.hasPrefix("Referenced from") && !$0.hasPrefix("Reason:") }) ?? output
    }

    @discardableResult
    static func run(_ arguments: [String], purpose: String, duration: Double? = nil, progress: ((Double) -> Void)? = nil) async throws -> ShellResult {
        guard let ffmpeg = path else { throw OpenTangerineError.ffmpegMissing(purpose) }
        var args = ["-hide_banner", "-y", "-nostdin"]
        if progress != nil { args += ["-progress", "pipe:1", "-loglevel", "error"] }
        args += arguments
        let result: ShellResult
        if let progress, let duration, duration > 0 {
            result = try await runStreaming(ffmpeg, args, duration: duration, progress: progress)
        } else {
            result = try await ConvertShell.run(ffmpeg, args)
        }
        guard result.succeeded else {
            throw OpenTangerineError.toolFailed("ffmpeg", summarize(result.stderr.isEmpty ? result.stdout : result.stderr))
        }
        return result
    }

    private static func runStreaming(_ executable: String, _ arguments: [String], duration: Double, progress: @escaping (Double) -> Void) async throws -> ShellResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = box.process
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                let output = PipeBuffer()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    output.set(stderr: errPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    let handle = outPipe.fileHandleForReading
                    var buffer = ""
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }
                        buffer += String(decoding: chunk, as: UTF8.self)
                        while let range = buffer.range(of: "\n") {
                            let line = String(buffer[..<range.lowerBound])
                            buffer.removeSubrange(..<range.upperBound)
                            if line.hasPrefix("out_time_ms="), let ms = Double(line.dropFirst(12)) {
                                let fraction = min(1, max(0, ms / 1_000_000 / duration))
                                DispatchQueue.main.async { progress(fraction) }
                            }
                        }
                    }
                    group.leave()
                }
                process.terminationHandler = { proc in
                    group.wait()
                    continuation.resume(returning: output.result(status: proc.terminationStatus))
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    static func probeDuration(_ url: URL) async -> Double? {
        guard let probe = probePath else { return nil }
        let result = try? await ConvertShell.run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path])
        return result.flatMap { Double($0.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = clamped - Double(hours * 3600 + minutes * 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, secs)
    }
}

