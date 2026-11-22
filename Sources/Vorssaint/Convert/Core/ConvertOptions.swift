// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a person can change for one conversion, set on the island's options
/// pane. Every field is optional: unset means the engine's own default.
struct ConvertOptions: Equatable {
    /// Lossy image quality, 0.05 to 1.
    var quality: Double?
    /// Longest side in pixels; larger images are scaled down, never up.
    var maxLongEdge: Int?
    /// Video: tallest frame in pixels, never scaled up.
    var maxHeight: Int?
    /// Video: constant rate factor for H.264 and VP9; lower is better.
    var videoCRF: Int?
    var removeAudio = false
    /// GIF output.
    var gifFPS = 12
    var gifWidth = 640
    /// Audio bitrate in bits per second.
    var audioBitrate: Int?
}
