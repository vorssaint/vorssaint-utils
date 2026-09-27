// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which family of sample a key plays. Raw values match the pack.json groups.
enum KeySoundGroup: String, CaseIterable, Codable {
    case alpha, space, enter, delete, modifier, function, arrow, other

    /// Missing groups borrow from these, in order.
    var fallbacks: [KeySoundGroup] {
        switch self {
        case .alpha: return [.other]
        case .other: return [.alpha]
        default: return [.other, .alpha]
        }
    }

    /// macOS virtual key codes (kVK_*) mapped to a sound family.
    static func group(forKeyCode code: Int64) -> KeySoundGroup {
        switch code {
        case 49: return .space
        case 36, 76: return .enter                          // Return, keypad Enter
        case 51, 117: return .delete                        // Delete, Forward Delete
        case 123, 124, 125, 126: return .arrow
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: return .modifier
        case 53,                                            // Escape
             122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,  // F1–F12
             105, 107, 113, 106, 64, 79, 80, 90,           // F13–F20
             115, 119, 116, 121:                            // Home, End, Page Up/Down
            return .function
        case 48, 71, 114: return .other                    // Tab, Clear, Help
        default: return .alpha
        }
    }

    static func isModifier(keyCode: Int64) -> Bool { (54...63).contains(keyCode) }
}

/// How hard a key was hit. Raw values match the pack.json strength folders.
enum KeySoundStrength: String, CaseIterable, Codable, Comparable {
    case soft, medium, hard, slam

    var index: Int { Self.allCases.firstIndex(of: self)! }
    static func < (a: Self, b: Self) -> Bool { a.index < b.index }

    /// Nearest available strength first, preferring the softer neighbour.
    var searchOrder: [KeySoundStrength] {
        Self.allCases.sorted {
            let da = abs($0.index - index), db = abs($1.index - index)
            return da == db ? $0 < $1 : da < db
        }
    }
}

/// A sound pack: `pack.json` next to its WAV folders.
struct KeySoundPackManifest: Decodable {
    let name: String
    let author: String?
    let license: String?
    let homepage: String?
    let sampleRate: Double?
    let groups: [String: [String: [String]]]
    let release: [String: [String]]?

    /// Relative sample paths for a press, with group and strength fallbacks.
    func pressSamples(_ group: KeySoundGroup, _ strength: KeySoundStrength) -> [String] {
        for g in [group] + group.fallbacks {
            guard let strengths = groups[g.rawValue] else { continue }
            for s in strength.searchOrder {
                if let files = strengths[s.rawValue], !files.isEmpty { return files }
            }
        }
        return []
    }

    func releaseSamples(_ group: KeySoundGroup) -> [String] {
        guard let release else { return [] }
        for g in [group] + group.fallbacks {
            if let files = release[g.rawValue], !files.isEmpty { return files }
        }
        return []
    }
}

struct KeySoundPackInfo: Identifiable, Hashable {
    let id: String          // folder name, persisted
    let name: String        // display name
    let hasRelease: Bool
    let url: URL
}

enum KeySoundPackCatalog {
    /// Packs ship inside the app bundle; a user folder can add more.
    static var searchRoots: [URL] {
        var roots: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("KeySoundPacks") {
            roots.append(bundled)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(support.appendingPathComponent("Vorssaint/KeySoundPacks"))
        }
        return roots
    }

    static func available(in roots: [URL] = searchRoots) -> [KeySoundPackInfo] {
        var seen = Set<String>()
        var packs: [KeySoundPackInfo] = []
        for root in roots {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
            for folder in folders {
                let id = folder.lastPathComponent
                guard !seen.contains(id), let manifest = load(folder) else { continue }
                seen.insert(id)
                packs.append(KeySoundPackInfo(id: id, name: manifest.name,
                                              hasRelease: manifest.release != nil, url: folder))
            }
        }
        return packs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func load(_ folder: URL) -> KeySoundPackManifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("pack.json")) else { return nil }
        return try? JSONDecoder().decode(KeySoundPackManifest.self, from: data)
    }
}

/// Turns an accelerometer spike into a strength. Absolute spike sizes vary by
/// Mac, desk and typing style, so the classifier normalises each hit against
/// a running estimate of this person's typical hit.
struct KeyVelocityClassifier {
    /// Resting noise sits near 0.0005 g on an M4 Air; anything below is no hit.
    var deadzone = 0.0012
    /// Ratio to a typical hit where each strength begins (typical ≈ 1.0).
    var mediumAt = 0.55
    var hardAt = 1.45
    var slamAt = 2.6
    private(set) var typicalPeak = 0.01
    private var hits = 0

    /// `sensitivity` > 1 makes hits count as harder.
    mutating func classify(peak: Double, sensitivity: Double) -> KeySoundStrength {
        let excess = max(0, peak - deadzone)
        // No measurable jolt usually means an external keyboard, whose hits the
        // MacBook cannot feel: play the neutral sound instead of the softest.
        guard excess > 0 else { return .medium }
        let ratio = excess / max(typicalPeak, 0.0005) * sensitivity
        // Learn quickly at first, then slowly; ignore extreme outliers.
        let rate = hits < 30 ? 0.15 : 0.03
        let clipped = min(excess, typicalPeak * 4)
        typicalPeak += (clipped - typicalPeak) * rate
        hits += 1
        switch ratio {
        case ..<mediumAt: return .soft
        case ..<hardAt: return .medium
        case ..<slamAt: return .hard
        default: return .slam
        }
    }
}
