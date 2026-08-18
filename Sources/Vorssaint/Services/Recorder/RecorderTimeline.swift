// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The editable timeline: what is kept, what is cut out of the middle, and
/// where the picture leans in.
///
/// Everything is keyed in the RECORDING's own time, never in the finished
/// video's time. That single choice is what makes cutting a piece out of the
/// middle safe: the pointer track, the zooms and anything else keyed to time
/// all keep pointing at the same moments, and only one function has to know
/// how the two clocks line up.
enum RecorderTimeline {

    // MARK: - Pieces

    /// A stretch of the recording that is thrown away.
    struct Cut: Codable, Equatable {
        var start: Double
        var end: Double

        var duration: Double { max(0, end - start) }
    }

    /// One lean-in. Generated from a click to begin with, then owned by
    /// whoever touches it: the recorder never quietly regenerates these,
    /// because that is how an editor loses somebody's work.
    struct ZoomSegment: Codable, Equatable, Identifiable {
        var id: UUID
        var start: Double
        var end: Double
        var amount: Double
        /// Where it looks, in the recorded area's own 0...1 space. Nil means
        /// follow the pointer, which is what an automatic zoom does.
        var focusX: Double?
        var focusY: Double?

        init(id: UUID = UUID(),
             start: Double,
             end: Double,
             amount: Double,
             focusX: Double? = nil,
             focusY: Double? = nil) {
            self.id = id
            self.start = start
            self.end = end
            self.amount = amount
            self.focusX = focusX
            self.focusY = focusY
        }

        var duration: Double { max(0, end - start) }

        var followsPointer: Bool { focusX == nil || focusY == nil }

        var focus: CGPoint? {
            guard let focusX, let focusY else { return nil }
            return CGPoint(x: focusX, y: focusY)
        }
    }

    /// Short enough to be a beat, long enough to be seen. A drag that would
    /// make a piece shorter than this stops instead of producing something
    /// that cannot be grabbed again.
    static let minimumSegment: Double = 0.4
    static let minimumCut: Double = 0.1

    // MARK: - Normalizing

    /// Cuts, in order, merged where they touch, inside the recording, and
    /// never so short that they would be invisible.
    static func normalized(cuts: [Cut], duration: Double) -> [Cut] {
        guard duration > 0 else { return [] }
        let clamped = cuts.compactMap { cut -> Cut? in
            guard cut.start.isFinite, cut.end.isFinite else { return nil }
            let start = max(0, min(cut.start, duration))
            let end = max(0, min(cut.end, duration))
            guard end - start >= minimumCut else { return nil }
            return Cut(start: start, end: end)
        }.sorted { $0.start < $1.start }

        var merged: [Cut] = []
        for cut in clamped {
            if var last = merged.last, cut.start <= last.end {
                last.end = max(last.end, cut.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(cut)
            }
        }
        return merged
    }

    /// Zooms in order and never overlapping. An overlap is resolved by moving
    /// the later one's start, not by dropping either: the person put both
    /// there on purpose.
    static func normalized(segments: [ZoomSegment], duration: Double) -> [ZoomSegment] {
        guard duration > 0 else { return [] }
        let clamped = segments.compactMap { segment -> ZoomSegment? in
            guard segment.start.isFinite, segment.end.isFinite, segment.amount.isFinite
            else { return nil }
            var copy = segment
            copy.start = max(0, min(segment.start, duration))
            copy.end = max(0, min(segment.end, duration))
            copy.amount = RecorderSupport.sanitizedZoomAmount(segment.amount)
            if let x = copy.focusX { copy.focusX = min(1, max(0, x)) }
            if let y = copy.focusY { copy.focusY = min(1, max(0, y)) }
            guard copy.duration >= minimumSegment else { return nil }
            return copy
        }.sorted { $0.start < $1.start }

        var result: [ZoomSegment] = []
        for var segment in clamped {
            if let last = result.last, segment.start < last.end {
                segment.start = last.end
                guard segment.duration >= minimumSegment else { continue }
            }
            result.append(segment)
        }
        return result
    }

    // MARK: - What is kept

    /// The stretches of the recording that survive the trim and the cuts, in
    /// order. This is the list the export turns into a composition, and the
    /// list the two clocks are derived from.
    static func keptRanges(trim: RecorderSupport.Trim, cuts: [Cut]) -> [ClosedRange<Double>] {
        guard trim.duration > 0 else { return [] }
        var ranges: [ClosedRange<Double>] = []
        var cursor = trim.start
        for cut in cuts.sorted(by: { $0.start < $1.start }) {
            let start = max(cut.start, trim.start)
            let end = min(cut.end, trim.end)
            guard end > start else { continue }
            if start > cursor { ranges.append(cursor...start) }
            cursor = max(cursor, end)
        }
        if trim.end > cursor { ranges.append(cursor...trim.end) }
        return ranges.filter { $0.upperBound - $0.lowerBound > 0.001 }
    }

    static func outputDuration(trim: RecorderSupport.Trim, cuts: [Cut]) -> Double {
        keptRanges(trim: trim, cuts: cuts).reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    /// Finished-video time to recording time. The composer draws frames the
    /// player and the export ask for, and they ask in finished-video time.
    static func sourceTime(forOutput output: Double,
                           trim: RecorderSupport.Trim,
                           cuts: [Cut]) -> Double {
        let ranges = keptRanges(trim: trim, cuts: cuts)
        guard !ranges.isEmpty else { return trim.start }
        var remaining = max(0, output)
        for range in ranges {
            let span = range.upperBound - range.lowerBound
            if remaining <= span { return range.lowerBound + remaining }
            remaining -= span
        }
        return ranges[ranges.count - 1].upperBound
    }

    /// Recording time to finished-video time, or nil when that moment was cut
    /// out and does not exist in the finished video at all.
    static func outputTime(forSource source: Double,
                           trim: RecorderSupport.Trim,
                           cuts: [Cut]) -> Double? {
        let ranges = keptRanges(trim: trim, cuts: cuts)
        var elapsed: Double = 0
        for range in ranges {
            if source < range.lowerBound { return nil }
            if source <= range.upperBound { return elapsed + (source - range.lowerBound) }
            elapsed += range.upperBound - range.lowerBound
        }
        return nil
    }

    // MARK: - Evaluating

    /// How far into a lean-in the picture is at a moment of the recording,
    /// how strong that lean-in is, and where it is aimed. Nothing is happening
    /// when the progress is zero.
    struct ZoomState: Equatable {
        var progress: Double
        var amount: Double
        var focus: CGPoint?
    }

    /// The segment that OWNS this moment always wins over the one before it
    /// fading out. Two zooms that touch have to hand over directly: reading
    /// the earlier one's ramp-out first would zoom the picture all the way
    /// back out and then snap into the second one.
    static func zoomState(at time: Double, segments: [ZoomSegment]) -> ZoomState {
        var fadingOut: ZoomSegment?
        for segment in segments {
            if time >= segment.start - 0.001, time <= segment.end {
                return state(of: segment, at: time)
            }
            if time > segment.end, time <= segment.end + RecorderMotion.zoomRampOut {
                fadingOut = segment
            }
        }
        guard let fadingOut else { return ZoomState(progress: 0, amount: 1, focus: nil) }
        return state(of: fadingOut, at: time)
    }

    private static func state(of segment: ZoomSegment, at time: Double) -> ZoomState {
        let rampIn = min(RecorderMotion.zoomRampIn, segment.duration / 2)
        let progress: Double
        if time >= segment.end {
            progress = RecorderMotion.smootherstep(
                1 - (time - segment.end) / RecorderMotion.zoomRampOut)
        } else if rampIn > 0, time <= segment.start + rampIn {
            progress = RecorderMotion.smootherstep((time - segment.start) / rampIn)
        } else {
            progress = 1
        }
        return ZoomState(progress: progress, amount: segment.amount, focus: segment.focus)
    }

    // MARK: - Generating and editing zooms

    /// The first set of zooms a recording gets, straight from its clicks.
    /// Produced ONCE, when a recording is opened and has none; after that they
    /// are the person's, and only an explicit ask rebuilds them.
    static func generatedSegments(clicks: [RecorderMotion.Click],
                                  typingTimes: [Double] = [],
                                  duration: Double,
                                  amount: Double) -> [ZoomSegment] {
        RecorderMotion.zoomSegments(clicks: clicks,
                                    typingTimes: typingTimes,
                                    duration: duration).map {
            ZoomSegment(start: $0.start, end: $0.end, amount: amount)
        }
    }

    /// Where a new zoom should go when the person adds one at the playhead:
    /// a comfortable default length, pushed off anything already there, and
    /// refused rather than squeezed when there is genuinely no room.
    static let addedSegmentLength: Double = 2.0

    static func slotForNewSegment(at time: Double,
                                  existing: [ZoomSegment],
                                  duration: Double) -> (start: Double, end: Double)? {
        guard duration > minimumSegment else { return nil }
        let ordered = existing.sorted { $0.start < $1.start }
        var start = max(0, min(time, duration - minimumSegment))
        // The gap the playhead is standing in.
        var limit = duration
        for segment in ordered {
            if segment.end <= start { continue }
            if segment.start <= start {
                // Standing inside a zoom: the new one starts where it ends.
                start = segment.end
                continue
            }
            limit = segment.start
            break
        }
        guard limit - start >= minimumSegment else { return nil }
        return (start: start, end: min(limit, start + addedSegmentLength))
    }

    /// Moving a whole segment, kept inside the recording and off its
    /// neighbours, so a drag can never produce an overlap to resolve later.
    static func moved(_ segment: ZoomSegment,
                      to start: Double,
                      among others: [ZoomSegment],
                      duration: Double) -> ZoomSegment {
        var moved = segment
        let span = segment.duration
        var lower: Double = 0
        var upper = duration
        for other in others where other.id != segment.id {
            if other.end <= segment.start { lower = max(lower, other.end) }
            if other.start >= segment.end { upper = min(upper, other.start) }
        }
        moved.start = max(lower, min(start, upper - span))
        moved.end = moved.start + span
        return moved
    }

    /// Dragging one edge. The opposite edge stays put and the segment can
    /// never be shortened past the point where it could be grabbed again.
    static func resized(_ segment: ZoomSegment,
                        edge: Edge,
                        to time: Double,
                        among others: [ZoomSegment],
                        duration: Double) -> ZoomSegment {
        var resized = segment
        var lower: Double = 0
        var upper = duration
        for other in others where other.id != segment.id {
            if other.end <= segment.start { lower = max(lower, other.end) }
            if other.start >= segment.end { upper = min(upper, other.start) }
        }
        switch edge {
        case .start:
            resized.start = max(lower, min(time, segment.end - minimumSegment))
        case .end:
            resized.end = min(upper, max(time, segment.start + minimumSegment))
        }
        return resized
    }

    enum Edge {
        case start
        case end
    }
}
