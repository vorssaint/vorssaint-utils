// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure policy and geometry for the screen recorder: everything that can be
/// decided without a stream, a writer or a window, so it can be reasoned about
/// and tested on its own.
enum RecorderSupport {

    // MARK: - What is being recorded

    /// The area a recording covers, resolved once when the person confirms it
    /// and never recomputed: a window that moves keeps recording the region it
    /// was picked in, which is what the pointer track and the zoom assume.
    struct Region: Equatable {
        let displayID: CGDirectDisplayID
        /// Set only when a window was clicked, so the stream can follow that
        /// window's own buffer instead of a slice of the display.
        let windowID: CGWindowID?
        /// Top-left origin, in the display's pixels, already even on both axes.
        let pixelRect: CGRect
        /// The same area in Cocoa global points, for anchoring panels to it.
        let anchorRect: CGRect
        /// Pixels per point of the source display.
        let scale: CGFloat

        var pixelSize: CGSize { pixelRect.size }
    }

    /// Video encoders reject or silently adjust odd dimensions, so the picked
    /// area is snapped before anything else sees it and the badge the person
    /// reads is the snapped number.
    static let minimumSide: CGFloat = 32

    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: evenSide(size.width), height: evenSide(size.height))
    }

    private static func evenSide(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return minimumSide }
        let rounded = max(minimumSide, value.rounded(.down))
        return rounded.truncatingRemainder(dividingBy: 2) == 0 ? rounded : rounded - 1
    }

    /// The picked rectangle in whole, even pixels, kept inside the display it
    /// came from. Shrinks rather than shifts when it would overflow, so the
    /// area never silently covers something the person did not choose.
    static func snappedPixelRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite
        else { return CGRect(origin: bounds.origin, size: evenSize(bounds.size)) }

        let clamped = rect.intersection(bounds).isNull ? bounds : rect.intersection(bounds)
        var origin = CGPoint(x: clamped.origin.x.rounded(.down),
                             y: clamped.origin.y.rounded(.down))
        var size = evenSize(clamped.size)
        if origin.x + size.width > bounds.maxX {
            origin.x = max(bounds.minX, (bounds.maxX - size.width).rounded(.down))
        }
        if origin.y + size.height > bounds.maxY {
            origin.y = max(bounds.minY, (bounds.maxY - size.height).rounded(.down))
        }
        size = evenSize(CGSize(width: min(size.width, bounds.maxX - origin.x),
                               height: min(size.height, bounds.maxY - origin.y)))
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Frame rate

    static let frameRates = [30, 60]

    static func sanitizedFrameRate(_ raw: Int) -> Int {
        frameRates.contains(raw) ? raw : 60
    }

    // MARK: - Quality

    /// Three named outcomes instead of a codec form. Screen content is
    /// low-entropy, so the encoder undershoots these ceilings hard; what the
    /// preset really decides is the output scale, and the ceiling only caps
    /// the busy moments.
    enum Quality: String, CaseIterable {
        case small, balanced, high

        var outputScale: CGFloat {
            switch self {
            case .small: return 0.5
            case .balanced: return 2.0 / 3.0
            case .high: return 1
            }
        }

        /// Bits per pixel per frame, from measurements on real screen content.
        var bitsPerPixel: Double {
            switch self {
            case .small: return 0.05
            case .balanced: return 0.082
            case .high: return 0.09
            }
        }

        /// A long group of pictures pays off on a screen that mostly sits
        /// still; the high preset keeps it short so scrubbing stays snappy.
        var keyframeSeconds: Double {
            switch self {
            case .small, .balanced: return 10
            case .high: return 2
            }
        }
    }

    static func sanitizedQuality(_ raw: String?) -> Quality {
        Quality(rawValue: raw ?? "") ?? .balanced
    }

    /// The encoder ceiling for a given output size, floored so a tiny area
    /// still gets a usable stream and capped so a full Retina display cannot
    /// ask for more than the media engine sustains.
    static func averageBitRate(width: Int, height: Int, fps: Int, quality: Quality) -> Int {
        let pixels = Double(max(1, width)) * Double(max(1, height))
        let raw = pixels * Double(max(1, fps)) * quality.bitsPerPixel
        return Int(min(max(raw, 800_000), 60_000_000).rounded())
    }

    /// The take is the master the editor works from, so it is encoded once at
    /// the top preset regardless of what the person picks for export.
    static let takeQuality: Quality = .high

    /// Output size for an export preset, always even.
    static func outputSize(source: CGSize, quality: Quality) -> CGSize {
        evenSize(CGSize(width: source.width * quality.outputScale,
                        height: source.height * quality.outputScale))
    }

    // MARK: - Canvas

    /// The shape of the finished picture. Original keeps the recording's own
    /// proportions; the others exist because a recording is usually going
    /// somewhere with a shape of its own.
    enum Aspect: String, CaseIterable {
        case original, wide, square, vertical

        var ratio: CGFloat? {
            switch self {
            case .original: return nil
            case .wide: return 16.0 / 9.0
            case .square: return 1
            case .vertical: return 9.0 / 16.0
            }
        }
    }

    static func sanitizedAspect(_ raw: String?) -> Aspect {
        Aspect(rawValue: raw ?? "") ?? .original
    }

    /// Nothing is ever encoded larger than this on its long edge: a background
    /// with a generous margin can otherwise ask for a picture much bigger than
    /// the recording it frames, for no visible gain.
    static let maximumCanvasEdge: CGFloat = 3840

    /// The whole picture, background included. The recording keeps its own
    /// pixels and the canvas grows around it, so a margin never costs sharpness.
    static func canvasSize(source: CGSize, padding: Double, aspect: Aspect) -> CGSize {
        guard source.width > 0, source.height > 0 else { return evenSize(source) }
        let margin = min(0.35, max(0, padding))
        let inner = 1 - 2 * margin
        guard inner > 0.05 else { return evenSize(source) }
        var width = source.width / inner
        var height = source.height / inner
        if let ratio = aspect.ratio {
            // Grow the short side until the shape matches; never crop.
            if width / height < ratio {
                width = height * ratio
            } else {
                height = width / ratio
            }
        }
        let longest = max(width, height)
        if longest > maximumCanvasEdge {
            let factor = maximumCanvasEdge / longest
            width *= factor
            height *= factor
        }
        return evenSize(CGSize(width: width, height: height))
    }

    /// Where the recording sits inside the canvas: centred, as large as the
    /// margin allows, keeping its own proportions.
    static func cardRect(canvas: CGSize, source: CGSize, padding: Double) -> CGRect {
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0
        else { return CGRect(origin: .zero, size: canvas) }
        let margin = min(0.35, max(0, padding))
        let available = CGSize(width: canvas.width * (1 - 2 * margin),
                               height: canvas.height * (1 - 2 * margin))
        let factor = min(available.width / source.width, available.height / source.height)
        let size = CGSize(width: (source.width * factor).rounded(),
                          height: (source.height * factor).rounded())
        return CGRect(x: ((canvas.width - size.width) / 2).rounded(),
                      y: ((canvas.height - size.height) / 2).rounded(),
                      width: size.width,
                      height: size.height)
    }

    /// How round the recording's corners are, as a share of its short side.
    static func cardCorner(_ factor: Double, cardSize: CGSize) -> CGFloat {
        let clamped = min(1, max(0, factor))
        return (clamped * min(cardSize.width, cardSize.height) * 0.09).rounded()
    }

    static let pointerSizeRange: ClosedRange<Double> = 0.5...2.0
    static let zoomAmountRange: ClosedRange<Double> = 1.2...3.0

    static func sanitizedPointerSize(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1 }
        return min(pointerSizeRange.upperBound, max(pointerSizeRange.lowerBound, raw))
    }

    static func sanitizedZoomAmount(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1.8 }
        return min(zoomAmountRange.upperBound, max(zoomAmountRange.lowerBound, raw))
    }

    /// How big the drawn pointer is in the recording's own pixels. Tied to the
    /// height of the picture so it reads the same on a small area and on a
    /// whole Retina display, and multiplied by the size the person was
    /// actually using while recording.
    static func pointerPixelSize(sourceSize: CGSize, userScale: Double, systemScale: Double) -> CGFloat {
        let base = max(24, sourceSize.height * 0.028)
        return (base * CGFloat(sanitizedPointerSize(userScale)) * CGFloat(max(1, systemScale)))
            .rounded()
    }

    // MARK: - Elapsed time

    /// "0:07" while it is short, "1:02:03" once it passes an hour. Minutes
    /// never carry a leading zero at the head of the label, the way a player
    /// shows a position.
    static func elapsedLabel(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Takes

    /// A recording is a small folder, not a file: the master, the pointer
    /// track and the edit live together so an edit can always be redone from
    /// the original pixels instead of from an already rendered result.
    static let takeVideoName = "take.mov"
    static let takePointerName = "pointer.bin"
    static let takeTypingName = "typing.json"
    static let takeEditName = "edit.json"
    static let takeFolderPrefix = "Take-"

    static func takeFolderName(id: UUID) -> String {
        takeFolderPrefix + id.uuidString
    }

    static func takeID(fromFolderName name: String) -> UUID? {
        guard name.hasPrefix(takeFolderPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(takeFolderPrefix.count)))
    }

    /// A recording only lives in its folder while its editor is open: closing
    /// the editor takes it with it, saved or not, so nothing invisible ever
    /// piles up. The only thing this sweep ever finds is a folder left behind
    /// by a crash or a quit. Age alone cannot tell the two apart, so the
    /// recordings that still have an editor are filtered out before this is
    /// asked anything; what reaches here is only what nobody owns.
    static let orphanMaxAge: TimeInterval = 24 * 3600
    /// A folder with no master yet is a recording that is still being written,
    /// or one that died before writing a single frame.
    static let unwrittenMaxAge: TimeInterval = 3600

    static func orphanTakeIDs(_ takes: [(id: UUID, finishedAt: Date?, createdAt: Date?)],
                              now: Date) -> [UUID] {
        takes.compactMap { take in
            if let finishedAt = take.finishedAt {
                return now.timeIntervalSince(finishedAt) > orphanMaxAge ? take.id : nil
            }
            guard let createdAt = take.createdAt else { return nil }
            return now.timeIntervalSince(createdAt) > unwrittenMaxAge ? take.id : nil
        }
    }

    // MARK: - Trim

    /// The kept part of a recording, in seconds. Always inside the recording
    /// and never shorter than a moment, so an accidental drag of both handles
    /// onto each other cannot produce an empty file.
    struct Trim: Equatable {
        var start: Double
        var end: Double

        var duration: Double { max(0, end - start) }
    }

    static let minimumTrimSeconds: Double = 0.2

    static func sanitizedTrim(start: Double, end: Double, duration: Double) -> Trim {
        guard duration > 0, duration.isFinite else { return Trim(start: 0, end: 0) }
        let floorEnd = end.isFinite && end > 0 ? min(end, duration) : duration
        let cappedStart = start.isFinite ? max(0, min(start, duration)) : 0
        let span = min(minimumTrimSeconds, duration)
        if floorEnd - cappedStart < span {
            // Whichever handle was dragged too far gives way, never the
            // recording: the result is always a clip you can actually play.
            let clampedStart = min(cappedStart, duration - span)
            return Trim(start: max(0, clampedStart), end: max(0, clampedStart) + span)
        }
        return Trim(start: cappedStart, end: floorEnd)
    }

    // MARK: - Filmstrip

    /// Evenly spaced sample times across the recording, one per thumbnail,
    /// taken at the middle of each slot so the strip reads as the film rather
    /// than as the two ends.
    static func filmstripTimes(duration: Double, count: Int) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        return (0..<count).map { index in
            (Double(index) + 0.5) / Double(count) * duration
        }
    }

    // MARK: - GIF

    /// A GIF holds every frame uncompressed while it is being written, so the
    /// only real defence against a recording that eats the memory of the
    /// machine is to keep the frame count and the picture small on purpose.
    enum GIFSize: String, CaseIterable {
        case small, medium, large

        var longEdge: CGFloat {
            switch self {
            case .small: return 420
            case .medium: return 600
            case .large: return 800
            }
        }
    }

    static func sanitizedGIFSize(_ raw: String?) -> GIFSize {
        GIFSize(rawValue: raw ?? "") ?? .medium
    }

    static let gifFrameRates = [8, 12, 15]
    static let maximumGIFFrames = 300

    static func sanitizedGIFFrameRate(_ raw: Int) -> Int {
        gifFrameRates.contains(raw) ? raw : 12
    }

    static func gifFrameCount(duration: Double, fps: Int) -> Int {
        guard duration > 0, fps > 0 else { return 0 }
        return max(1, Int((duration * Double(fps)).rounded(.down)))
    }

    /// Whether a clip fits inside the frame budget at the chosen rate, and
    /// how long it would have to be to fit. Answering this before the person
    /// commits is the difference between a clear limit and a hang.
    static func gifFitsBudget(duration: Double, fps: Int) -> Bool {
        gifFrameCount(duration: duration, fps: fps) <= maximumGIFFrames
    }

    static func maximumGIFSeconds(fps: Int) -> Double {
        guard fps > 0 else { return 0 }
        return Double(maximumGIFFrames) / Double(fps)
    }

    /// GIF delay below 100 ms is silently clamped by readers unless the
    /// unclamped key is written too, so anything above 10 fps needs both.
    static func gifDelay(fps: Int) -> Double {
        1 / Double(max(1, fps))
    }

    static func gifOutputSize(source: CGSize, size: GIFSize) -> CGSize {
        let longest = max(source.width, source.height)
        guard longest > 0 else { return CGSize(width: size.longEdge, height: size.longEdge) }
        let factor = min(1, size.longEdge / longest)
        return evenSize(CGSize(width: source.width * factor, height: source.height * factor))
    }

    // MARK: - Disk

    /// Refusing to start is a much better failure than filling the disk mid
    /// recording, so both ends are guarded: a floor to begin at all, and a
    /// lower floor that stops a recording already running.
    static let minimumFreeBytesToStart: Int64 = 2_000_000_000
    static let minimumFreeBytesToContinue: Int64 = 500_000_000

    static func canStart(freeBytes: Int64) -> Bool {
        freeBytes >= minimumFreeBytesToStart
    }

    static func shouldStopForDisk(freeBytes: Int64) -> Bool {
        freeBytes < minimumFreeBytesToContinue
    }

    /// Rough size of one second of master, used only to tell the person what
    /// a long recording will cost before they start one.
    static func estimatedBytesPerSecond(pixelSize: CGSize, fps: Int) -> Int64 {
        let bits = averageBitRate(width: Int(pixelSize.width),
                                  height: Int(pixelSize.height),
                                  fps: fps,
                                  quality: takeQuality)
        return Int64(Double(bits) / 8)
    }
}
