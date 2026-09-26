// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// A part of the picture kept unreadable for a while: a name, an address, a
/// number that should not travel with the video.
///
/// The area lives in the recorded picture's own 0...1 space with a top-left
/// origin, like a zoom's focus, so it stays on the same pixels whatever
/// shape, quality or zoom the finished video ends up with. Unlike a caption
/// it never fades: a blur that eases in shows what it is hiding.
struct RecorderBlurRegion: Codable, Equatable, Identifiable, RecorderTimelineBlock {
    var id: UUID
    /// In the recording's own time, like everything else on the timeline.
    var start: Double
    var end: Double
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// How hard the area is hidden, on the screenshot editor's 1...5 scale.
    var strength: Int

    init(id: UUID = UUID(),
         start: Double,
         end: Double,
         rect: CGRect = defaultRect,
         strength: Int = ScreenshotSupport.BlurStrength.defaultLevel) {
        self.id = id
        self.start = start
        self.end = end
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
        self.strength = strength
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, x, y, width, height, strength
    }

    /// Blurs saved before the strength existed open at the strength they
    /// were drawn with.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        strength = try container.decodeIfPresent(Int.self, forKey: .strength)
            ?? ScreenshotSupport.BlurStrength.defaultLevel
    }

    var duration: Double { max(0, end - start) }

    /// Where the blur sits, in the recorded picture's 0...1 top-left space.
    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Where a new blur lands before the person draws its area: in the middle,
    /// big enough to be seen, never mistaken for the whole picture.
    static let defaultRect = CGRect(x: 0.35, y: 0.4, width: 0.3, height: 0.2)
    /// Smaller than this and it cannot be seen or grabbed again.
    static let minimumSide: Double = 0.01

    /// Hard edges on purpose: what is hidden is hidden on every frame it
    /// covers, and there is no frame where it is half there.
    func covers(_ time: Double) -> Bool {
        time >= start && time <= end
    }

    /// The area in pixels of a picture of `size`, counted from the bottom the
    /// way Core Image does.
    func pixelRect(in size: CGSize) -> CGRect {
        CGRect(x: CGFloat(x) * size.width,
               y: (1 - CGFloat(y + height)) * size.height,
               width: CGFloat(width) * size.width,
               height: CGFloat(height) * size.height).integral
    }

    /// The drawn area, clamped inside the picture and never so thin that it
    /// vanishes; nil when it is not an area at all.
    static func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect? {
        func clamped(_ value: CGFloat) -> CGFloat { min(1, max(0, value)) }
        let minX = clamped(min(first.x, second.x))
        let maxX = clamped(max(first.x, second.x))
        let minY = clamped(min(first.y, second.y))
        let maxY = clamped(max(first.y, second.y))
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard rect.width >= minimumSide, rect.height >= minimumSide else { return nil }
        return rect
    }

    func sanitized(duration recordingDuration: Double) -> RecorderBlurRegion? {
        guard recordingDuration > 0, start.isFinite, end.isFinite,
              x.isFinite, y.isFinite, width.isFinite, height.isFinite
        else { return nil }
        var copy = self
        copy.start = max(0, min(start, recordingDuration))
        copy.end = max(0, min(end, recordingDuration))
        guard copy.duration >= 0.2 else { return nil }
        guard let rect = Self.normalizedRect(from: rect.origin,
                                             to: CGPoint(x: rect.maxX, y: rect.maxY))
        else { return nil }
        copy.x = Double(rect.origin.x)
        copy.y = Double(rect.origin.y)
        copy.width = Double(rect.width)
        copy.height = Double(rect.height)
        copy.strength = ScreenshotSupport.BlurStrength.sanitized(strength)
        return copy
    }

    static func normalized(_ regions: [RecorderBlurRegion],
                           duration: Double) -> [RecorderBlurRegion] {
        regions.compactMap { $0.sanitized(duration: duration) }
            .sorted { $0.start < $1.start }
    }
}
