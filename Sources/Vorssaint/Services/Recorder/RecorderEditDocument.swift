// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Everything the editor can change about a recording, as one value.
///
/// It is a value type on purpose: undo keeps a stack of these, which costs
/// bytes, where the screenshot editor's undo keeps whole images. Nothing here
/// touches the master, so any edit can be taken back at any point, including
/// after the file has already been exported once.
struct RecorderEditDocument: Codable, Equatable {
    /// Kept part of the recording, in seconds. An end of zero means "to the
    /// end", so a document written before the recording's duration was known
    /// still opens showing everything.
    var trimStart: Double
    var trimEnd: Double
    var quality: String
    var keepsSystemAudio: Bool
    var gifSize: String
    var gifFrameRate: Int
    /// The background behind the recording, as the same JSON the screenshot
    /// tool writes, so a look saved in one tool is understood by the other.
    var backdrop: String
    var aspect: String
    var showsPointer: Bool
    var pointerSmoothing: String
    var pointerSize: Double
    var showsClickRing: Bool
    var zoomEnabled: Bool
    var zoomAmount: Double
    /// Whether automatic click zooms stay on the clicked field while typing.
    var zoomsOnTyping: Bool
    /// Stretches thrown away from the middle, in the recording's own time.
    var cuts: [RecorderTimeline.Cut]
    /// The lean-ins. Filled once from the clicks when a recording is first
    /// opened, and owned by the person from then on.
    var zoomSegments: [RecorderTimeline.ZoomSegment]
    /// Set the moment the first set is generated, so opening the recording
    /// again never regenerates over hand edits, including the edit of
    /// deleting every zoom.
    var zoomsGenerated: Bool
    /// Lines of text laid over the recording, in the recording's own time.
    var texts: [RecorderTextOverlay]
    var keepsMicrophone: Bool
    var systemAudioGain: Double
    var microphoneGain: Double

    init(trimStart: Double = 0,
         trimEnd: Double = 0,
         quality: String = RecorderSupport.Quality.balanced.rawValue,
         keepsSystemAudio: Bool = true,
         gifSize: String = RecorderSupport.GIFSize.medium.rawValue,
         gifFrameRate: Int = 12,
         backdrop: String = "",
         aspect: String = RecorderSupport.Aspect.original.rawValue,
         showsPointer: Bool = true,
         pointerSmoothing: String = RecorderMotion.Smoothing.smooth.rawValue,
         pointerSize: Double = 1,
         showsClickRing: Bool = true,
         zoomEnabled: Bool = true,
         zoomAmount: Double = 1.8,
         zoomsOnTyping: Bool = false,
         cuts: [RecorderTimeline.Cut] = [],
         zoomSegments: [RecorderTimeline.ZoomSegment] = [],
         zoomsGenerated: Bool = false,
         texts: [RecorderTextOverlay] = [],
         keepsMicrophone: Bool = true,
         systemAudioGain: Double = 1,
         microphoneGain: Double = 1) {
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.quality = quality
        self.keepsSystemAudio = keepsSystemAudio
        self.gifSize = gifSize
        self.gifFrameRate = gifFrameRate
        self.backdrop = backdrop
        self.aspect = aspect
        self.showsPointer = showsPointer
        self.pointerSmoothing = pointerSmoothing
        self.pointerSize = pointerSize
        self.showsClickRing = showsClickRing
        self.zoomEnabled = zoomEnabled
        self.zoomAmount = zoomAmount
        self.zoomsOnTyping = zoomsOnTyping
        self.cuts = cuts
        self.zoomSegments = zoomSegments
        self.zoomsGenerated = zoomsGenerated
        self.texts = texts
        self.keepsMicrophone = keepsMicrophone
        self.systemAudioGain = systemAudioGain
        self.microphoneGain = microphoneGain
    }

    /// A document written before these fields existed still opens: every one
    /// of them falls back to the same value a new recording would get.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trimStart = try container.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(Double.self, forKey: .trimEnd) ?? 0
        quality = try container.decodeIfPresent(String.self, forKey: .quality)
            ?? RecorderSupport.Quality.balanced.rawValue
        keepsSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .keepsSystemAudio) ?? true
        gifSize = try container.decodeIfPresent(String.self, forKey: .gifSize)
            ?? RecorderSupport.GIFSize.medium.rawValue
        gifFrameRate = try container.decodeIfPresent(Int.self, forKey: .gifFrameRate) ?? 12
        backdrop = try container.decodeIfPresent(String.self, forKey: .backdrop) ?? ""
        aspect = try container.decodeIfPresent(String.self, forKey: .aspect)
            ?? RecorderSupport.Aspect.original.rawValue
        showsPointer = try container.decodeIfPresent(Bool.self, forKey: .showsPointer) ?? true
        pointerSmoothing = try container.decodeIfPresent(String.self, forKey: .pointerSmoothing)
            ?? RecorderMotion.Smoothing.smooth.rawValue
        pointerSize = try container.decodeIfPresent(Double.self, forKey: .pointerSize) ?? 1
        showsClickRing = try container.decodeIfPresent(Bool.self, forKey: .showsClickRing) ?? true
        zoomEnabled = try container.decodeIfPresent(Bool.self, forKey: .zoomEnabled) ?? true
        zoomAmount = try container.decodeIfPresent(Double.self, forKey: .zoomAmount) ?? 1.8
        zoomsOnTyping = try container.decodeIfPresent(Bool.self, forKey: .zoomsOnTyping) ?? false
        cuts = try container.decodeIfPresent([RecorderTimeline.Cut].self, forKey: .cuts) ?? []
        zoomSegments = try container.decodeIfPresent([RecorderTimeline.ZoomSegment].self,
                                                     forKey: .zoomSegments) ?? []
        zoomsGenerated = try container.decodeIfPresent(Bool.self, forKey: .zoomsGenerated) ?? false
        texts = try container.decodeIfPresent([RecorderTextOverlay].self, forKey: .texts) ?? []
        keepsMicrophone = try container.decodeIfPresent(Bool.self, forKey: .keepsMicrophone) ?? true
        systemAudioGain = try container.decodeIfPresent(Double.self, forKey: .systemAudioGain) ?? 1
        microphoneGain = try container.decodeIfPresent(Double.self, forKey: .microphoneGain) ?? 1
    }

    // MARK: - Timeline

    func trimmed(duration: Double) -> RecorderSupport.Trim {
        trim(duration: duration)
    }

    func keptRanges(duration: Double) -> [ClosedRange<Double>] {
        RecorderTimeline.keptRanges(trim: trim(duration: duration),
                                    cuts: RecorderTimeline.normalized(cuts: cuts,
                                                                      duration: duration))
    }

    func outputDuration(duration: Double) -> Double {
        RecorderTimeline.outputDuration(trim: trim(duration: duration),
                                        cuts: RecorderTimeline.normalized(cuts: cuts,
                                                                          duration: duration))
    }

    /// The zooms as they will actually be applied: normalized, and empty when
    /// the person switched the whole effect off.
    func activeZoomSegments(duration: Double) -> [RecorderTimeline.ZoomSegment] {
        guard zoomEnabled else { return [] }
        return RecorderTimeline.normalized(segments: zoomSegments, duration: duration)
    }

    /// Turning automatic zoom back on is an explicit request to recover the
    /// click-based zooms when the timeline was emptied by mistake.
    func restoringAutomaticZooms(clicks: [RecorderMotion.Click],
                                 typingTimes: [Double] = [],
                                 duration: Double) -> RecorderEditDocument {
        guard zoomEnabled, zoomSegments.isEmpty else { return self }
        let generated = RecorderTimeline.generatedSegments(
            clicks: clicks,
            typingTimes: typingTimes,
            duration: duration,
            amount: RecorderSupport.sanitizedZoomAmount(zoomAmount))
        guard !generated.isEmpty else { return self }
        var next = self
        next.zoomSegments = generated
        next.zoomsGenerated = true
        return next
    }

    var resolvedBackdrop: ScreenshotSupport.BackdropStyle {
        ScreenshotSupport.BackdropStyle.decoded(backdrop)
    }

    var resolvedAspect: RecorderSupport.Aspect {
        RecorderSupport.sanitizedAspect(aspect)
    }

    var resolvedSmoothing: RecorderMotion.Smoothing {
        RecorderMotion.sanitizedSmoothing(pointerSmoothing)
    }

    /// The three looks the person can land on with one click. Nothing is
    /// stored about which one is active: a look is a set of values, so
    /// changing anything afterwards is just changing a value.
    enum Look: String, CaseIterable {
        case raw, clean, studio
    }

    func applying(_ look: Look) -> RecorderEditDocument {
        var next = self
        switch look {
        case .raw:
            // The recording exactly as it happened. The pointer is still drawn,
            // because the capture itself never contains one, but nothing is
            // smoothed and nothing is added.
            next.backdrop = ""
            next.aspect = RecorderSupport.Aspect.original.rawValue
            next.showsPointer = true
            next.pointerSmoothing = RecorderMotion.Smoothing.off.rawValue
            next.showsClickRing = false
            next.zoomEnabled = false
        case .clean:
            next.backdrop = ""
            next.aspect = RecorderSupport.Aspect.original.rawValue
            next.showsPointer = true
            next.pointerSmoothing = RecorderMotion.Smoothing.smooth.rawValue
            next.showsClickRing = true
            next.zoomEnabled = true
        case .studio:
            next.backdrop = ScreenshotSupport.BackdropStyle(
                kind: .preset,
                presetID: ScreenshotSupport.BackdropID.graphite.rawValue,
                padding: 0.45,
                cornerRadius: 0.35).encoded()
            next.showsPointer = true
            next.pointerSmoothing = RecorderMotion.Smoothing.smooth.rawValue
            next.showsClickRing = true
            next.zoomEnabled = true
        }
        return next
    }

    func matches(_ look: Look) -> Bool {
        let expected = applying(look)
        return backdrop == expected.backdrop
            && aspect == expected.aspect
            && showsPointer == expected.showsPointer
            && pointerSmoothing == expected.pointerSmoothing
            && showsClickRing == expected.showsClickRing
            && zoomEnabled == expected.zoomEnabled
    }

    var resolvedQuality: RecorderSupport.Quality {
        RecorderSupport.sanitizedQuality(quality)
    }

    var resolvedGIFSize: RecorderSupport.GIFSize {
        RecorderSupport.sanitizedGIFSize(gifSize)
    }

    var resolvedGIFFrameRate: Int {
        RecorderSupport.sanitizedGIFFrameRate(gifFrameRate)
    }

    func trim(duration: Double) -> RecorderSupport.Trim {
        RecorderSupport.sanitizedTrim(start: trimStart, end: trimEnd, duration: duration)
    }

    /// Whether two documents would draw a different picture. Trim and audio
    /// do not, so dragging a handle never rebuilds the preview pipeline.
    func affectsPicture(_ other: RecorderEditDocument) -> Bool {
        backdrop != other.backdrop
            || aspect != other.aspect
            || showsPointer != other.showsPointer
            || pointerSmoothing != other.pointerSmoothing
            || pointerSize != other.pointerSize
            || showsClickRing != other.showsClickRing
            || zoomEnabled != other.zoomEnabled
            || zoomAmount != other.zoomAmount
            || zoomSegments != other.zoomSegments
            || cuts != other.cuts
            || texts != other.texts
    }

    /// Whether the finished video would run differently, which is what forces
    /// the preview to be rebuilt from a new composition rather than just
    /// redrawn.
    func affectsTiming(_ other: RecorderEditDocument) -> Bool {
        cuts != other.cuts || trimStart != other.trimStart || trimEnd != other.trimEnd
    }

    func affectsAudio(_ other: RecorderEditDocument) -> Bool {
        keepsSystemAudio != other.keepsSystemAudio
            || keepsMicrophone != other.keepsMicrophone
            || systemAudioGain != other.systemAudioGain
            || microphoneGain != other.microphoneGain
    }

    /// True once the person has actually changed something worth warning about
    /// before the window closes.
    func isEdited(duration: Double) -> Bool {
        let trim = trim(duration: duration)
        return trim.start > 0.01 || trim.end < duration - 0.01 || !keepsSystemAudio
            || !keepsMicrophone || systemAudioGain != 1 || microphoneGain != 1
            || !cuts.isEmpty || !zoomSegments.isEmpty || !texts.isEmpty
    }

    /// A damaged or hand-edited document can never wedge the editor: every
    /// field falls back to something usable.
    func sanitized(duration: Double) -> RecorderEditDocument {
        var document = self
        let trim = trim(duration: duration)
        document.trimStart = trim.start
        document.trimEnd = trim.end
        document.quality = resolvedQuality.rawValue
        document.gifSize = resolvedGIFSize.rawValue
        document.gifFrameRate = resolvedGIFFrameRate
        document.aspect = resolvedAspect.rawValue
        document.pointerSmoothing = resolvedSmoothing.rawValue
        document.pointerSize = RecorderSupport.sanitizedPointerSize(pointerSize)
        document.zoomAmount = RecorderSupport.sanitizedZoomAmount(zoomAmount)
        document.systemAudioGain = RecorderSupport.sanitizedAudioGain(systemAudioGain)
        document.microphoneGain = RecorderSupport.sanitizedAudioGain(microphoneGain)
        let backdropStyle = resolvedBackdrop
        document.backdrop = backdropStyle.kind == .none ? "" : backdropStyle.encoded()
        document.cuts = RecorderTimeline.normalized(cuts: cuts, duration: duration)
        document.zoomSegments = RecorderTimeline.normalized(segments: zoomSegments,
                                                            duration: duration)
        document.texts = RecorderTextOverlay.normalized(texts, duration: duration)
        return document
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(_ data: Data?) -> RecorderEditDocument {
        guard let data, let document = try? JSONDecoder().decode(RecorderEditDocument.self, from: data)
        else { return RecorderEditDocument() }
        return document
    }
}

/// A named visual starting point. Timeline edits, captions and sound are never
/// part of a preset, so applying one cannot undo real editing work.
struct RecorderEditPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let backdrop: String
    let aspect: String
    let showsPointer: Bool
    let pointerSmoothing: String
    let pointerSize: Double
    let showsClickRing: Bool
    let zoomEnabled: Bool
    let zoomAmount: Double

    init(id: UUID = UUID(), name: String, document: RecorderEditDocument) {
        self.id = id
        self.name = name
        backdrop = document.backdrop
        aspect = document.aspect
        showsPointer = document.showsPointer
        pointerSmoothing = document.pointerSmoothing
        pointerSize = document.pointerSize
        showsClickRing = document.showsClickRing
        zoomEnabled = document.zoomEnabled
        zoomAmount = document.zoomAmount
    }

    func applying(to document: RecorderEditDocument) -> RecorderEditDocument {
        var next = document
        next.backdrop = backdrop
        next.aspect = aspect
        next.showsPointer = showsPointer
        next.pointerSmoothing = pointerSmoothing
        next.pointerSize = pointerSize
        next.showsClickRing = showsClickRing
        next.zoomEnabled = zoomEnabled
        next.zoomAmount = zoomAmount
        return next
    }
}
