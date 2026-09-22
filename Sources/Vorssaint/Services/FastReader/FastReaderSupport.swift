// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where Fast Reader shows what it is reading. Phase 1 ships only
/// `.floating`; `.notch` is reserved for the Dynamic Island surface planned
/// for Phase 2 and is accepted here so an early preference value does not
/// need to change again once that surface exists.
enum FastReaderSurface: String {
    case floating
    case notch

    /// A stored value that predates this case set, or one hand-edited into
    /// something unrecognized, must still resolve to a surface Fast Reader
    /// can actually draw. `.floating` is the only surface Phase 1 implements,
    /// so it is also the safe fallback.
    init(storageValue: String?) {
        self = storageValue.flatMap(FastReaderSurface.init(rawValue:)) ?? .floating
    }
}

/// Bridges the `DefaultsKey.fastReader*` preferences to the pure engine's
/// `ReaderOptions`. Every numeric value is clamped into the engine's own
/// range on the way out: the engine already clamps internally before it
/// divides, but doing it again here means a preference file edited by hand,
/// or one carried over from a build that shipped a wider range, can never
/// reach the session with a value the engine would have had to correct for
/// it anyway.
enum FastReaderPreferences {
    static func options(from defaults: UserDefaults = .standard) -> ReaderOptions {
        var options = ReaderOptions.default
        options.wordsPerMinute = clamp(defaults.integer(forKey: DefaultsKey.fastReaderWordsPerMinute),
                                       fallback: options.wordsPerMinute,
                                       to: FastReaderEngine.wordsPerMinuteRange)
        options.chunkSize = clamp(defaults.integer(forKey: DefaultsKey.fastReaderChunkSize),
                                  fallback: options.chunkSize,
                                  to: FastReaderEngine.chunkSizeRange)
        options.focusPoint = defaults.bool(forKey: DefaultsKey.fastReaderFocusPoint)
        options.punctuationPause = defaults.bool(forKey: DefaultsKey.fastReaderPunctuationPause)
        options.longWordScaling = defaults.bool(forKey: DefaultsKey.fastReaderLongWordScaling)
        return options
    }

    static var surface: FastReaderSurface {
        FastReaderSurface(storageValue: UserDefaults.standard.string(forKey: DefaultsKey.fastReaderSurface))
    }

    /// `UserDefaults.integer(forKey:)` answers zero for a key that was never
    /// written, which is inside every range Fast Reader clamps here but is
    /// not what an unset preference should mean. Zero is only ever trusted
    /// when it is actually in range; anything else, including a genuine
    /// zero that is out of range, falls back to the engine's own default
    /// before clamping.
    private static func clamp(_ stored: Int, fallback: Int, to range: ClosedRange<Int>) -> Int {
        let value = stored == 0 && !range.contains(0) ? fallback : stored
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
