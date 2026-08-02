// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// A line of text that appears over the recording for a while.
///
/// Placed on a corner or an edge rather than dragged to an arbitrary spot:
/// nine places cover what people actually do with a caption, they read at a
/// glance, and they keep working when the shape of the video changes.
struct RecorderTextOverlay: Codable, Equatable, Identifiable {

    enum Anchor: String, Codable, CaseIterable {
        case topLeading, top, topTrailing
        case leading, center, trailing
        case bottomLeading, bottom, bottomTrailing

        /// Where the text sits, 0...1 with a top-left origin, before the
        /// margin is taken off.
        var unitPoint: CGPoint {
            switch self {
            case .topLeading: return CGPoint(x: 0, y: 0)
            case .top: return CGPoint(x: 0.5, y: 0)
            case .topTrailing: return CGPoint(x: 1, y: 0)
            case .leading: return CGPoint(x: 0, y: 0.5)
            case .center: return CGPoint(x: 0.5, y: 0.5)
            case .trailing: return CGPoint(x: 1, y: 0.5)
            case .bottomLeading: return CGPoint(x: 0, y: 1)
            case .bottom: return CGPoint(x: 0.5, y: 1)
            case .bottomTrailing: return CGPoint(x: 1, y: 1)
            }
        }
    }

    /// A short list rather than a colour well: every one of these is legible
    /// over a screen recording, which an arbitrary colour is not.
    enum Palette: String, Codable, CaseIterable {
        case white, black, accent, yellow, red, green

        var components: (red: Double, green: Double, blue: Double) {
            switch self {
            case .white: return (1, 1, 1)
            case .black: return (0.06, 0.06, 0.07)
            case .accent: return (0.04, 0.52, 1.00)
            case .yellow: return (1.00, 0.80, 0.00)
            case .red: return (0.96, 0.26, 0.21)
            case .green: return (0.20, 0.78, 0.35)
            }
        }
    }

    var id: UUID
    var text: String
    /// In the recording's own time, like everything else on the timeline.
    var start: Double
    var end: Double
    var anchor: Anchor
    /// Height of the type as a share of the picture's height.
    var size: Double
    var palette: Palette

    init(id: UUID = UUID(),
         text: String,
         start: Double,
         end: Double,
         anchor: Anchor = .bottom,
         size: Double = 0.06,
         palette: Palette = .white) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.anchor = anchor
        self.size = size
        self.palette = palette
    }

    var duration: Double { max(0, end - start) }

    static let sizeRange: ClosedRange<Double> = 0.03...0.16
    static let defaultLength: Double = 3.0
    static let fade: Double = 0.25

    /// How solid the text is at a moment, eased at both ends so it never
    /// appears or vanishes on a single frame.
    func opacity(at time: Double) -> Double {
        guard duration > 0 else { return 0 }
        let ramp = min(Self.fade, duration / 2)
        if time < start || time > end { return 0 }
        if ramp <= 0 { return 1 }
        if time < start + ramp {
            return RecorderMotion.smoothstep((time - start) / ramp)
        }
        if time > end - ramp {
            return RecorderMotion.smoothstep((end - time) / ramp)
        }
        return 1
    }

    func sanitized(duration recordingDuration: Double) -> RecorderTextOverlay? {
        guard recordingDuration > 0, start.isFinite, end.isFinite else { return nil }
        var copy = self
        copy.text = String(text.prefix(200))
        copy.start = max(0, min(start, recordingDuration))
        copy.end = max(0, min(end, recordingDuration))
        copy.size = size.isFinite
            ? min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, size))
            : 0.06
        guard copy.duration >= 0.2 else { return nil }
        return copy
    }

    static func normalized(_ overlays: [RecorderTextOverlay],
                           duration: Double) -> [RecorderTextOverlay] {
        overlays.compactMap { $0.sanitized(duration: duration) }
            .sorted { $0.start < $1.start }
    }
}
