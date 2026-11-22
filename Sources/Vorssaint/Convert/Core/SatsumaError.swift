// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

enum OpenTangerineError: LocalizedError {
    case unsupportedConversion(FileFormat, FileFormat)
    case unreadable(URL)
    case encodeFailed(String)
    case ffmpegMissing(String)
    case toolFailed(String, String)
    case cancelled
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedConversion(from, to):
            return "Converting \(from.displayName) to \(to.displayName) is not supported."
        case let .unreadable(url):
            return "Could not read \(url.lastPathComponent)."
        case let .encodeFailed(what):
            return "Could not write \(what)."
        case let .ffmpegMissing(what):
            return "\(what) needs ffmpeg. Install it (for example with `brew install ffmpeg`) or set its path in Settings."
        case let .toolFailed(tool, output):
            return "\(tool) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .cancelled:
            return "Cancelled."
        case let .invalidInput(reason):
            return reason
        }
    }
}

