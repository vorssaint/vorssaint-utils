// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

enum CompressionPreset: String, CaseIterable, Identifiable {
    case balanced
    case strong

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var imageQuality: Double { self == .balanced ? 0.72 : 0.5 }
    var videoScale: Double { self == .balanced ? 1.0 : 0.75 }
    var videoBitrateFactor: Double { self == .balanced ? 0.6 : 0.35 }
    var audioBitrate: Int { self == .balanced ? 128_000 : 64_000 }
}

enum OutputLocation: String, CaseIterable, Identifiable {
    case besideOriginal, downloads, desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .besideOriginal: return "Beside the original"
        case .downloads: return "Downloads"
        case .desktop: return "Desktop"
        }
    }

    func directory(for source: URL) -> URL {
        switch self {
        case .besideOriginal: return source.deletingLastPathComponent()
        case .downloads: return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .desktop: return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
    }
}

/// The few settings the converters read, kept in Vorssaint's own defaults.
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard
    private init() {}

    var jpegQuality: Double {
        get { defaults.object(forKey: DefaultsKey.convertJPEGQuality) as? Double ?? 0.9 }
        set { defaults.set(newValue, forKey: DefaultsKey.convertJPEGQuality) }
    }
    var ffmpegPath: String {
        get { defaults.string(forKey: DefaultsKey.convertFFmpegPath) ?? "" }
        set { defaults.set(newValue, forKey: DefaultsKey.convertFFmpegPath) }
    }
    var outputLocation: OutputLocation {
        get { OutputLocation(rawValue: defaults.string(forKey: DefaultsKey.convertOutputLocation) ?? "") ?? .besideOriginal }
        set { defaults.set(newValue.rawValue, forKey: DefaultsKey.convertOutputLocation) }
    }
    var revealInFinder: Bool {
        get { defaults.object(forKey: DefaultsKey.convertRevealInFinder) as? Bool ?? false }
        set { defaults.set(newValue, forKey: DefaultsKey.convertRevealInFinder) }
    }
    var compressionPreset: CompressionPreset {
        get { CompressionPreset(rawValue: defaults.string(forKey: DefaultsKey.convertCompressionPreset) ?? "") ?? .balanced }
        set { defaults.set(newValue.rawValue, forKey: DefaultsKey.convertCompressionPreset) }
    }
    var compressionResizeLongEdge: Int {
        get { defaults.integer(forKey: DefaultsKey.convertResizeLongEdge) }
        set { defaults.set(newValue, forKey: DefaultsKey.convertResizeLongEdge) }
    }
}
