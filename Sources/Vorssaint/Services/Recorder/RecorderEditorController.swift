// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// What the editor view watches. Holds the document, the player and the
/// filmstrip; every change goes through here so undo has one thing to record.
final class RecorderEditorModel: ObservableObject, BackdropEditing {
    enum ExportPhase: Equatable {
        case saving
        case compressing
        case uploading
    }

    enum ShareFailure: Error {
        case tooLarge
        case failed
        case cancelled
    }

    let take: RecorderTakeStore.Take
    let player: AVPlayer

    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var thumbnails: [CGImage] = []
    @Published private(set) var isExporting = false
    @Published private(set) var exportProgress: Double = 0
    @Published private(set) var exportPhase: ExportPhase = .saving
    /// The last file this recording produced. Kept so the editor can hand it
    /// over: a HUD naming a folder is not the same as giving somebody the file.
    @Published private(set) var lastExportedURL: URL?
    @Published private(set) var editPresets: [RecorderEditPreset] = []
    @Published private(set) var audioWaveforms: [RecorderAudioSource: [Float]] = [:]
    @Published var document: RecorderEditDocument {
        didSet { documentDidChange(from: oldValue) }
    }

    /// Undo keeps whole documents. They are a few dozen bytes each, so the
    /// stack can be deep without the cost the screenshot editor pays for
    /// snapshotting images.
    fileprivate var undoStack: [RecorderEditDocument] = []
    fileprivate var redoStack: [RecorderEditDocument] = []
    fileprivate var suppressUndo = false

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var timeObserver: Any?
    private var thumbnailTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var compositionTask: Task<Void, Never>?
    private lazy var sourceAsset = AVURLAsset(url: take.videoURL)
    /// How long the finished video is, which is what the transport shows.
    @Published private(set) var outputDuration: Double = 0
    private(set) var sourceSize: CGSize = .zero
    private var sourceFrameRate = 60
    private var audioTrackIDs: [RecorderAudioSource: CMPersistentTrackID] = [:]
    private(set) var audioSources: Set<RecorderAudioSource> = []
    private(set) var pointerTrack = RecorderPointerTrack()
    private(set) var typingTrack = RecorderTypingTrack()
    /// True when the recording carries a pointer track at all. Without one the
    /// pointer and zoom controls have nothing to act on and are hidden rather
    /// than shown doing nothing.
    var hasPointerTrack: Bool { !pointerTrack.isEmpty }
    private var typingTimes: [Double] {
        document.zoomsOnTyping ? typingTrack.times : []
    }

    var trim: RecorderSupport.Trim {
        document.trim(duration: duration)
    }

    init(take: RecorderTakeStore.Take) {
        self.take = take
        let item = AVPlayerItem(url: take.videoURL)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        // A recording opened for the first time starts from the person's own
        // preferences; after that the edit next to the master wins, so
        // reopening finds exactly what was left behind.
        if let saved = try? Data(contentsOf: take.editURL) {
            document = RecorderEditDocument.decoded(saved)
        } else {
            let defaults = UserDefaults.standard
            document = RecorderEditDocument(
                quality: RecorderSupport.sanitizedQuality(
                    defaults.string(forKey: DefaultsKey.recorderQuality)).rawValue,
                keepsSystemAudio: defaults.bool(forKey: DefaultsKey.recorderSystemAudio),
                gifSize: RecorderSupport.sanitizedGIFSize(
                    defaults.string(forKey: DefaultsKey.recorderGIFSize)).rawValue,
                gifFrameRate: RecorderSupport.sanitizedGIFFrameRate(
                    defaults.integer(forKey: DefaultsKey.recorderGIFFrameRate)),
                zoomEnabled: defaults.bool(forKey: DefaultsKey.recorderAutomaticZoom))
        }
        player.isMuted = false
        pointerTrack = RecorderPointerTrack.decoded(try? Data(contentsOf: take.pointerURL))
        typingTrack = RecorderTypingTrack.decoded(try? Data(contentsOf: take.typingURL))
        loadEditPresets()
        loadBackdropPresets()
        observeTime()
        load()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        thumbnailTask?.cancel()
        waveformTask?.cancel()
        previewTask?.cancel()
        compositionTask?.cancel()
    }

    // MARK: - Loading

    private func load() {
        Task { @MainActor [weak self] in
            guard let self,
                  let seconds = try? await self.sourceAsset.load(.duration)
            else { return }
            self.duration = max(0, CMTimeGetSeconds(seconds))
            if let track = try? await self.sourceAsset.loadTracks(withMediaType: .video).first {
                let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
                let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
                self.sourceSize = RecorderSupport.videoGeometry(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform).size
                let rate = (try? await track.load(.nominalFrameRate)) ?? 60
                self.sourceFrameRate = RecorderSupport.sanitizedFrameRate(Int(rate.rounded()))
            }
            let audioTracks = await RecorderAudioSource.tracks(in: self.sourceAsset)
            self.audioSources = Set(audioTracks.keys)
            self.loadAudioWaveforms(audioTracks)
            self.document = self.document.sanitized(duration: self.duration)
            self.generateZoomsIfNeeded()
            self.loadThumbnails()
            self.rebuildComposition()
        }
    }

    /// What the player actually plays: the kept stretches, joined. Building it
    /// is what makes a piece cut out of the middle genuinely absent while
    /// scrubbing instead of skipped over by a player pretending.
    func rebuildComposition() {
        compositionTask?.cancel()
        guard duration > 0 else { return }
        let ranges = document.keptRanges(duration: duration)
        let asset = sourceAsset
        compositionTask = Task { @MainActor [weak self] in
            guard let result = await RecorderComposition.build(from: asset,
                                                               ranges: ranges,
                                                               includesAudio: true),
                  let self, !Task.isCancelled
            else { return }
            let item = AVPlayerItem(asset: result.asset)
            self.audioTrackIDs = result.audioTrackIDs
            item.audioMix = RecorderComposition.audioMix(trackIDs: result.audioTrackIDs,
                                                         document: self.document)
            self.player.replaceCurrentItem(with: item)
            self.player.isMuted = false
            self.outputDuration = CMTimeGetSeconds(result.duration)
            self.rebuildPreview()
        }
    }

    private func loadAudioWaveforms(_ tracks: [RecorderAudioSource: AVAssetTrack]) {
        waveformTask?.cancel()
        let duration = duration
        let asset = sourceAsset
        waveformTask = Task.detached(priority: .utility) { [weak self] in
            var waveforms: [RecorderAudioSource: [Float]] = [:]
            for source in RecorderAudioSource.allCases {
                guard let track = tracks[source], !Task.isCancelled else { continue }
                waveforms[source] = RecorderAudioWaveform.load(asset: asset,
                                                               track: track,
                                                               duration: duration,
                                                               count: 220)
            }
            guard !Task.isCancelled else { return }
            let result = waveforms
            await MainActor.run { [weak self] in self?.audioWaveforms = result }
        }
    }

    private func loadThumbnails() {
        let url = take.videoURL
        let times = RecorderSupport.filmstripTimes(duration: duration, count: 14)
        guard !times.isEmpty else { return }
        thumbnailTask = Task.detached(priority: .userInitiated) { [weak self] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 240)
            // The strip is a rough map of the recording, not a frame-accurate
            // ruler, so a generous tolerance buys a much faster load.
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            var images: [CGImage] = []
            for seconds in times {
                if Task.isCancelled { return }
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let image = try? await generator.image(at: time).image else { continue }
                images.append(image)
            }
            let result = images
            await MainActor.run { [weak self] in
                self?.thumbnails = result
            }
        }
    }

    // MARK: - Playback

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600),
            queue: .main) { [weak self] time in
                guard let self else { return }
                // The player runs on the FINISHED video's clock; the strip,
                // the lane and everything else run on the recording's. One
                // conversion, in one place.
                self.currentTime = CMTimeGetSeconds(time)
                if self.isPlaying, self.currentTime >= self.outputDuration - 0.02 {
                    self.pause()
                    self.seekOutput(to: 0)
                }
            }
    }

    /// Where the playhead is in the RECORDING, which is what the timeline draws.
    var sourceTime: Double {
        RecorderTimeline.sourceTime(forOutput: currentTime,
                                    trim: document.trim(duration: duration),
                                    cuts: RecorderTimeline.normalized(cuts: document.cuts,
                                                                      duration: duration))
    }

    private func seekOutput(to seconds: Double) {
        let clamped = max(0, min(seconds, max(0, outputDuration)))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero)
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// The playhead is already on the FINISHED video's clock, and so is the
    /// composition the player holds: the trim is baked into it. So the only
    /// thing play has to catch is a playhead sitting at the very end, which
    /// would otherwise play nothing.
    func play() {
        if outputDuration > 0, currentTime >= outputDuration - 0.05 {
            seekOutput(to: 0)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// Takes a moment of the RECORDING. A moment that was cut out lands on
    /// the nearest one that still exists, so the playhead can never sit in a
    /// place the video does not have.
    func seek(to seconds: Double) {
        let trim = document.trim(duration: duration)
        let cuts = RecorderTimeline.normalized(cuts: document.cuts, duration: duration)
        if let output = RecorderTimeline.outputTime(forSource: seconds, trim: trim, cuts: cuts) {
            seekOutput(to: output)
            return
        }
        let ranges = RecorderTimeline.keptRanges(trim: trim, cuts: cuts)
        guard let nearest = ranges.min(by: {
            abs($0.lowerBound - seconds) < abs($1.lowerBound - seconds)
        }) else { return }
        seek(to: nearest.lowerBound)
    }

    // MARK: - Editing

    func setTrimStart(_ seconds: Double) {
        var next = document
        next.trimStart = seconds
        next.trimEnd = document.trimEnd == 0 ? duration : document.trimEnd
        document = next.sanitized(duration: duration)
        seek(to: trim.start)
    }

    func setTrimEnd(_ seconds: Double) {
        var next = document
        next.trimEnd = seconds
        document = next.sanitized(duration: duration)
        seek(to: max(trim.start, trim.end - 0.05))
    }

    func toggleSound() {
        toggleAudio(.system)
    }

    func toggleAudio(_ source: RecorderAudioSource) {
        var next = document
        switch source {
        case .system: next.keepsSystemAudio.toggle()
        case .microphone: next.keepsMicrophone.toggle()
        }
        document = next
    }

    func setAudioGain(_ gain: Double, for source: RecorderAudioSource) {
        var next = document
        switch source {
        case .system: next.systemAudioGain = RecorderSupport.sanitizedAudioGain(gain)
        case .microphone: next.microphoneGain = RecorderSupport.sanitizedAudioGain(gain)
        }
        document = next
    }

    func keepsAudio(_ source: RecorderAudioSource) -> Bool {
        switch source {
        case .system: return document.keepsSystemAudio
        case .microphone: return document.keepsMicrophone
        }
    }

    func audioGain(_ source: RecorderAudioSource) -> Double {
        switch source {
        case .system: return document.systemAudioGain
        case .microphone: return document.microphoneGain
        }
    }

    func hasAudio(_ source: RecorderAudioSource) -> Bool {
        audioSources.contains(source)
    }

    private func applyAudioMix() {
        player.currentItem?.audioMix = RecorderComposition.audioMix(trackIDs: audioTrackIDs,
                                                                    document: document)
    }

    private func documentDidChange(from previous: RecorderEditDocument) {
        guard !suppressUndo, previous != document else { return }
        undoStack.append(previous)
        redoStack.removeAll()
        persist()
        if previous.affectsTiming(document) {
            rebuildComposition()
        } else if previous.affectsAudio(document) {
            applyAudioMix()
        } else if previous.affectsPicture(document) {
            rebuildPreview()
        }
    }

    /// The preview is the export, one frame at a time: the same composer draws
    /// both, so what is watched here cannot disagree with what is written.
    /// Rebuilt after a beat so dragging a slider does not thrash it.
    fileprivate func rebuildPreview() {
        previewTask?.cancel()
        guard duration > 0, sourceSize.width > 0 else { return }
        let document = document
        let track = pointerTrack
        let sourceSize = sourceSize
        let frameRate = sourceFrameRate
        let duration = duration
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self, let item = self.player.currentItem else { return }
            guard let plan = RecorderComposer.makePlan(document: document,
                                                       track: track,
                                                       sourceSize: sourceSize,
                                                       frameRate: frameRate,
                                                       duration: duration) else {
                item.videoComposition = nil
                return
            }
            let composer = RecorderComposer(plan: plan)
            let asset = item.asset
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  !Task.isCancelled
            else { return }
            let composition = await RecorderComposer.videoComposition(
                track: videoTrack,
                asset: asset,
                duration: CMTime(seconds: duration, preferredTimescale: 600),
                frameRate: frameRate,
                composer: composer,
                sourceSize: sourceSize,
                outputSize: composer.canvasSize)
            guard !Task.isCancelled else { return }
            item.videoComposition = composition
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        apply(next)
    }

    private func apply(_ next: RecorderEditDocument) {
        let previous = document
        suppressUndo = true
        document = next
        suppressUndo = false
        player.isMuted = false
        persist()
        if previous.affectsTiming(next) {
            rebuildComposition()
        } else if previous.affectsAudio(next) {
            applyAudioMix()
        } else if previous.affectsPicture(next) {
            rebuildPreview()
        }
        seek(to: trim.start)
    }

    func applyLook(_ look: RecorderEditDocument.Look) {
        document = document.applying(look).restoringAutomaticZooms(
            clicks: pointerTrack.clicks,
            typingTimes: typingTimes,
            duration: duration)
    }

    func applyPreset(_ preset: RecorderEditPreset) {
        document = preset.applying(to: document)
            .restoringAutomaticZooms(clicks: pointerTrack.clicks,
                                     typingTimes: typingTimes,
                                     duration: duration)
            .sanitized(duration: duration)
    }

    func savePreset(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let index = editPresets.firstIndex(where: {
            $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            editPresets[index] = RecorderEditPreset(id: editPresets[index].id,
                                                    name: clean,
                                                    document: document)
        } else {
            editPresets.append(RecorderEditPreset(name: clean, document: document))
            editPresets = Array(editPresets.suffix(12))
        }
        persistEditPresets()
    }

    func removePreset(_ preset: RecorderEditPreset) {
        editPresets.removeAll { $0.id == preset.id }
        persistEditPresets()
    }

    private func loadEditPresets() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.recorderEditorPresets),
              let presets = try? JSONDecoder().decode([RecorderEditPreset].self, from: data)
        else { return }
        editPresets = Array(presets.suffix(12))
    }

    private func persistEditPresets() {
        guard let data = try? JSONEncoder().encode(editPresets) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.recorderEditorPresets)
    }

    /// The edit lives next to the master, so reopening a recording finds it
    /// exactly as it was left.
    fileprivate func persist() {
        guard let data = document.encoded() else { return }
        try? data.write(to: take.editURL, options: .atomic)
    }

    /// The size the current preset will write, for THIS recording.
    var exportSize: CGSize {
        guard sourceSize.width > 0 else { return .zero }
        let style = document.resolvedBackdrop
        let padding = style.kind == .none ? 0 : style.padding * 0.18
        let canvas = RecorderSupport.canvasSize(source: sourceSize,
                                                padding: padding,
                                                aspect: document.resolvedAspect,
                                                cropsToAspect: style.kind == .none)
        return RecorderSupport.outputSize(source: canvas, quality: document.resolvedQuality)
    }

    // MARK: - Cutting

    /// The stretch of the recording picked out on the filmstrip, waiting to be
    /// removed. In the recording's own time, like everything else.
    @Published var cutSelection: ClosedRange<Double>?

    func setCutSelection(_ range: ClosedRange<Double>?) {
        guard let range else {
            cutSelection = nil
            return
        }
        let lower = max(0, min(range.lowerBound, duration))
        let upper = max(0, min(range.upperBound, duration))
        guard upper - lower >= RecorderTimeline.minimumCut else {
            cutSelection = nil
            return
        }
        cutSelection = lower...upper
    }

    var canCutSelection: Bool {
        guard let cutSelection else { return false }
        // Never let a cut take the whole recording with it.
        let trim = document.trim(duration: duration)
        var proposed = document.cuts
        proposed.append(RecorderTimeline.Cut(start: cutSelection.lowerBound,
                                             end: cutSelection.upperBound))
        let left = RecorderTimeline.outputDuration(
            trim: trim,
            cuts: RecorderTimeline.normalized(cuts: proposed, duration: duration))
        return left >= RecorderTimeline.minimumSegment
    }

    func cutSelectedRange() {
        guard let range = cutSelection, canCutSelection else { return }
        beginInteraction()
        var next = document
        next.cuts.append(RecorderTimeline.Cut(start: range.lowerBound, end: range.upperBound))
        next.cuts = RecorderTimeline.normalized(cuts: next.cuts, duration: duration)
        applyDuringInteraction(next)
        cutSelection = nil
        commitZoomEdit()
        rebuildComposition()
        seek(to: range.lowerBound)
    }

    /// Puts back the cut a seam belongs to, for whoever cut one piece too many.
    func restoreCut(at time: Double) {
        guard let index = document.cuts.firstIndex(where: {
            time >= $0.start - 0.15 && time <= $0.end + 0.15
        }) else { return }
        beginInteraction()
        var next = document
        next.cuts.remove(at: index)
        applyDuringInteraction(next)
        commitZoomEdit()
        rebuildComposition()
    }

    // MARK: - Zooms

    @Published var selectedZoomID: UUID?
    /// A drag is one edit, not one per mouse-moved: the document changes
    /// freely while the finger is down and the whole thing lands on the undo
    /// stack once, when it is let go.
    private var interactionSnapshot: RecorderEditDocument?
    /// What a new zoom inherits, so the second one matches the first without
    /// anybody setting anything.
    private var lastZoomAmount: Double?

    var selectedZoom: RecorderTimeline.ZoomSegment? {
        guard let selectedZoomID else { return nil }
        return zoom(selectedZoomID)
    }

    var canCreateAutomaticZooms: Bool {
        !RecorderTimeline.generatedSegments(
            clicks: pointerTrack.clicks,
            typingTimes: typingTimes,
            duration: duration,
            amount: document.zoomAmount).isEmpty
    }

    func setAutomaticZoomEnabled(_ enabled: Bool) {
        var next = document
        next.zoomEnabled = enabled
        if enabled {
            next = next.restoringAutomaticZooms(clicks: pointerTrack.clicks,
                                                typingTimes: typingTimes,
                                                duration: duration)
        }
        document = next
    }

    func setTypingZoomEnabled(_ enabled: Bool) {
        var next = document
        next.zoomsOnTyping = enabled
        next.zoomSegments = RecorderTimeline.generatedSegments(
            clicks: pointerTrack.clicks,
            typingTimes: enabled ? typingTrack.times : [],
            duration: duration,
            amount: RecorderSupport.sanitizedZoomAmount(next.zoomAmount))
        next.zoomEnabled = true
        next.zoomsGenerated = true
        document = next
    }

    func zoom(_ id: UUID) -> RecorderTimeline.ZoomSegment? {
        document.zoomSegments.first { $0.id == id }
    }

    func selectZoom(_ id: UUID?) {
        selectedZoomID = id
    }

    /// The first set of zooms a recording gets, from its own clicks. Done once
    /// and remembered as done, so reopening never writes over hand edits,
    /// including the edit of having deleted them all.
    private func generateZoomsIfNeeded() {
        guard !document.zoomsGenerated, duration > 0 else { return }
        var next = document.restoringAutomaticZooms(clicks: pointerTrack.clicks,
                                                    typingTimes: typingTimes,
                                                    duration: duration)
        next.zoomsGenerated = true
        suppressUndo = true
        document = next
        suppressUndo = false
        persist()
    }

    func addZoom(at time: Double) {
        guard duration > 0,
              let slot = RecorderTimeline.slotForNewSegment(at: time,
                                                            existing: document.zoomSegments,
                                                            duration: duration)
        else { return }
        beginInteraction()
        let segment = RecorderTimeline.ZoomSegment(
            start: slot.start,
            end: slot.end,
            amount: lastZoomAmount ?? RecorderSupport.sanitizedZoomAmount(document.zoomAmount))
        var next = document
        next.zoomSegments.append(segment)
        next.zoomEnabled = true
        next.zoomsGenerated = true
        applyDuringInteraction(next)
        selectedZoomID = segment.id
        commitZoomEdit()
    }

    func moveZoom(_ id: UUID, to start: Double) {
        guard let segment = zoom(id) else { return }
        beginInteraction()
        var next = document
        let moved = RecorderTimeline.moved(segment,
                                           to: start,
                                           among: next.zoomSegments,
                                           duration: duration)
        next.zoomSegments = next.zoomSegments.map { $0.id == id ? moved : $0 }
        applyDuringInteraction(next)
    }

    func resizeZoom(_ id: UUID, edge: RecorderTimeline.Edge, to time: Double) {
        guard let segment = zoom(id) else { return }
        beginInteraction()
        var next = document
        let resized = RecorderTimeline.resized(segment,
                                               edge: edge,
                                               to: time,
                                               among: next.zoomSegments,
                                               duration: duration)
        next.zoomSegments = next.zoomSegments.map { $0.id == id ? resized : $0 }
        applyDuringInteraction(next)
    }

    func setSelectedZoomAmount(_ amount: Double) {
        guard let id = selectedZoomID else { return }
        beginInteraction()
        var next = document
        next.zoomSegments = next.zoomSegments.map { segment -> RecorderTimeline.ZoomSegment in
            guard segment.id == id else { return segment }
            var copy = segment
            copy.amount = RecorderSupport.sanitizedZoomAmount(amount)
            return copy
        }
        lastZoomAmount = RecorderSupport.sanitizedZoomAmount(amount)
        applyDuringInteraction(next)
    }

    /// Where a hand-aimed zoom looks. Nil puts it back on following the
    /// pointer, which is what an automatic one does.
    func setSelectedZoomFocus(_ focus: CGPoint?) {
        guard let id = selectedZoomID else { return }
        beginInteraction()
        var next = document
        next.zoomSegments = next.zoomSegments.map { segment -> RecorderTimeline.ZoomSegment in
            guard segment.id == id else { return segment }
            var copy = segment
            copy.focusX = focus.map { min(1, max(0, Double($0.x))) }
            copy.focusY = focus.map { min(1, max(0, Double($0.y))) }
            return copy
        }
        applyDuringInteraction(next)
        commitZoomEdit()
    }

    func removeSelectedZoom() {
        guard let id = selectedZoomID else { return }
        beginInteraction()
        var next = document
        next.zoomSegments.removeAll { $0.id == id }
        applyDuringInteraction(next)
        selectedZoomID = nil
        commitZoomEdit()
    }

    /// Puts every zoom back the way the clicks would have made them, for
    /// whoever edited themselves into a corner.
    func regenerateZooms() {
        guard duration > 0 else { return }
        beginInteraction()
        var next = document
        next.zoomSegments = RecorderTimeline.generatedSegments(
            clicks: pointerTrack.clicks,
            typingTimes: typingTimes,
            duration: duration,
            amount: RecorderSupport.sanitizedZoomAmount(document.zoomAmount))
        next.zoomEnabled = true
        next.zoomsGenerated = true
        applyDuringInteraction(next)
        selectedZoomID = nil
        commitZoomEdit()
    }

    /// True while the next click on the picture sets where the selected zoom
    /// looks, instead of playing or pausing.
    @Published var isAimingZoom = false

    func beginAiming() {
        guard selectedZoomID != nil else { return }
        pause()
        isAimingZoom = true
    }

    /// A click on the stage, turned into a spot in the recorded area's own
    /// 0...1 space so a later change of shape or quality cannot invalidate it.
    func aim(at location: CGPoint, in viewSize: CGSize) {
        defer { isAimingZoom = false }
        guard sourceSize.width > 0, sourceSize.height > 0,
              viewSize.width > 0, viewSize.height > 0
        else { return }
        // The picture is letterboxed inside the stage, so the empty bands on
        // either side have to come off before the click means anything.
        let fit = min(viewSize.width / sourceSize.width, viewSize.height / sourceSize.height)
        let shown = CGSize(width: sourceSize.width * fit, height: sourceSize.height * fit)
        let originX = (viewSize.width - shown.width) / 2
        let originY = (viewSize.height - shown.height) / 2
        let u = (location.x - originX) / shown.width
        let v = (location.y - originY) / shown.height
        guard u >= 0, u <= 1, v >= 0, v <= 1 else { return }
        setSelectedZoomFocus(CGPoint(x: u, y: v))
    }

    private func beginInteraction() {
        guard interactionSnapshot == nil else { return }
        interactionSnapshot = document
    }

    private func applyDuringInteraction(_ next: RecorderEditDocument) {
        suppressUndo = true
        document = next
        suppressUndo = false
    }

    /// End of a drag: one undo entry for the whole thing, one save, one
    /// rebuild of the preview.
    func commitZoomEdit() {
        guard let snapshot = interactionSnapshot else { return }
        interactionSnapshot = nil
        guard snapshot != document else { return }
        undoStack.append(snapshot)
        redoStack.removeAll()
        persist()
        rebuildPreview()
    }

    // MARK: - Lanes

    /// Both lanes speak the same language to the view, so there is one set of
    /// gestures to learn and one implementation to keep right.
    @Published var selectedTextID: UUID?

    var selectedText: RecorderTextOverlay? {
        guard let selectedTextID else { return nil }
        return document.texts.first { $0.id == selectedTextID }
    }

    func laneItems(_ kind: RecorderZoomLane.Kind) -> [RecorderZoomLane.Item] {
        switch kind {
        case .zoom:
            return document.zoomSegments.map {
                RecorderZoomLane.Item(id: $0.id,
                                      start: $0.start,
                                      end: $0.end,
                                      label: String(format: "%.1fx", $0.amount),
                                      glyph: $0.followsPointer ? "\u{2197}" : "\u{25C9}")
            }
        case .text:
            return document.texts.map {
                RecorderZoomLane.Item(id: $0.id,
                                      start: $0.start,
                                      end: $0.end,
                                      label: String($0.text.prefix(18)),
                                      glyph: "T")
            }
        }
    }

    func laneSelection(_ kind: RecorderZoomLane.Kind) -> UUID? {
        kind == .zoom ? selectedZoomID : selectedTextID
    }

    func selectLaneItem(_ kind: RecorderZoomLane.Kind, id: UUID?) {
        switch kind {
        case .zoom:
            selectedZoomID = id
            if id != nil { selectedTextID = nil }
        case .text:
            selectedTextID = id
            if id != nil { selectedZoomID = nil }
        }
    }

    func addLaneItem(_ kind: RecorderZoomLane.Kind, at time: Double) {
        switch kind {
        case .zoom: addZoom(at: time)
        case .text: addText(at: time)
        }
    }

    func moveLaneItem(_ kind: RecorderZoomLane.Kind, id: UUID, to start: Double) {
        switch kind {
        case .zoom:
            moveZoom(id, to: start)
        case .text:
            guard let overlay = document.texts.first(where: { $0.id == id }) else { return }
            beginInteraction()
            var next = document
            let span = overlay.duration
            let clamped = max(0, min(start, duration - span))
            next.texts = next.texts.map { item -> RecorderTextOverlay in
                guard item.id == id else { return item }
                var copy = item
                copy.start = clamped
                copy.end = clamped + span
                return copy
            }
            applyDuringInteraction(next)
        }
    }

    func resizeLaneItem(_ kind: RecorderZoomLane.Kind,
                        id: UUID,
                        edge: RecorderTimeline.Edge,
                        to time: Double) {
        switch kind {
        case .zoom:
            resizeZoom(id, edge: edge, to: time)
        case .text:
            guard let overlay = document.texts.first(where: { $0.id == id }) else { return }
            beginInteraction()
            var next = document
            next.texts = next.texts.map { item -> RecorderTextOverlay in
                guard item.id == id else { return item }
                var copy = item
                switch edge {
                case .start: copy.start = max(0, min(time, overlay.end - 0.4))
                case .end: copy.end = min(duration, max(time, overlay.start + 0.4))
                }
                return copy
            }
            applyDuringInteraction(next)
        }
    }

    func removeSelectedLaneItem(_ kind: RecorderZoomLane.Kind) {
        switch kind {
        case .zoom: removeSelectedZoom()
        case .text: removeSelectedText()
        }
    }

    // MARK: - Text

    func addText(at time: Double) {
        guard duration > 0 else { return }
        beginInteraction()
        let start = max(0, min(time, max(0, duration - 0.4)))
        let overlay = RecorderTextOverlay(
            text: FeatureStrings.recorder(L10n.shared.language).textPlaceholder,
            start: start,
            end: min(duration, start + RecorderTextOverlay.defaultLength))
        var next = document
        next.texts.append(overlay)
        applyDuringInteraction(next)
        selectLaneItem(.text, id: overlay.id)
        commitZoomEdit()
    }

    func updateSelectedText(_ change: (inout RecorderTextOverlay) -> Void) {
        guard let id = selectedTextID else { return }
        beginInteraction()
        var next = document
        next.texts = next.texts.map { item -> RecorderTextOverlay in
            guard item.id == id else { return item }
            var copy = item
            change(&copy)
            return copy
        }
        applyDuringInteraction(next)
    }

    func removeSelectedText() {
        guard let id = selectedTextID else { return }
        beginInteraction()
        var next = document
        next.texts.removeAll { $0.id == id }
        applyDuringInteraction(next)
        selectedTextID = nil
        commitZoomEdit()
    }

    // MARK: - Background

    /// The saved looks are the SAME list the screenshot tool keeps, so a
    /// background built once is available in both places.
    @Published private(set) var backdropPresets: [ScreenshotSupport.BackdropStyle] = []

    var backdropStyle: ScreenshotSupport.BackdropStyle {
        get { document.resolvedBackdrop }
        set {
            var next = document
            let sanitized = newValue.sanitized()
            next.backdrop = sanitized.kind == .none ? "" : sanitized.encoded()
            document = next
        }
    }

    var showsBackdrop: Bool { document.resolvedBackdrop.kind != .none }

    func loadBackdropPresets() {
        backdropPresets = ScreenshotSupport.decodedBackdropPresets(
            UserDefaults.standard.string(forKey: DefaultsKey.screenshotBackdropPresets))
    }

    func saveCurrentBackdropAsPreset() {
        let style = backdropStyle.sanitized()
        guard style.kind != .none, style.kind != .preset else { return }
        var snapshot = style
        // A saved look is the look, not this recording's sliders.
        snapshot.padding = 0.5
        snapshot.cornerRadius = 0.1
        snapshot.blur = 0
        guard !backdropPresets.contains(where: {
            var candidate = $0
            candidate.padding = 0.5
            candidate.cornerRadius = 0.1
            candidate.blur = 0
            return candidate == snapshot
        }) else { return }
        backdropPresets = Array((backdropPresets + [snapshot])
            .suffix(ScreenshotSupport.backdropPresetLimit))
        persistPresets()
    }

    func removeBackdropPreset(at index: Int) {
        guard backdropPresets.indices.contains(index) else { return }
        backdropPresets.remove(at: index)
        persistPresets()
    }

    private func persistPresets() {
        UserDefaults.standard.set(ScreenshotSupport.encodedBackdropPresets(backdropPresets),
                                  forKey: DefaultsKey.screenshotBackdropPresets)
    }

    // MARK: - Export

    private var exporter: RecorderExporter?
    private var shareTask: Task<Void, Never>?

    func export(_ output: RecorderExporter.Output,
                to destination: URL,
                rememberDestination: Bool = true,
                completion: @escaping (RecorderExporter.Failure?) -> Void) {
        guard !isExporting else { return }
        pause()
        isExporting = true
        exportProgress = 0
        exportPhase = .saving
        let exporter = RecorderExporter()
        self.exporter = exporter
        let document = document
        let take = take
        Task { @MainActor [weak self] in
            let failure = await exporter.export(take: take,
                                                document: document,
                                                output: output,
                                                to: destination) { value in
                DispatchQueue.main.async { [weak self] in
                    self?.exportProgress = value
                }
            }
            guard let self else { return }
            self.isExporting = false
            self.exporter = nil
            if failure == nil, rememberDestination { self.lastExportedURL = destination }
            completion(failure)
        }
    }

    func share(_ duration: RecordingShareDuration,
               completion: @escaping (Result<RecordingShareRecord, ShareFailure>) -> Void) {
        guard !isExporting else { return }
        pause()
        isExporting = true
        exportProgress = 0
        exportPhase = .compressing
        let exporter = RecorderExporter()
        self.exporter = exporter
        let document = document
        let take = take
        shareTask = Task { @MainActor [weak self] in
            let result = await exporter.exportForSharing(
                take: take,
                document: document) { value in
                    DispatchQueue.main.async { [weak self] in
                        self?.exportProgress = value
                    }
                }
            guard let self else {
                result.artifact?.discard()
                return
            }
            if let failure = result.failure {
                self.finishSharing()
                switch failure {
                case .cancelled:
                    completion(.failure(.cancelled))
                case .tooLargeForSharing:
                    completion(.failure(.tooLarge))
                default:
                    completion(.failure(.failed))
                }
                return
            }
            guard let artifact = result.artifact else {
                self.finishSharing()
                completion(.failure(.failed))
                return
            }
            if Task.isCancelled {
                artifact.discard()
                self.finishSharing()
                completion(.failure(.cancelled))
                return
            }
            self.exportPhase = .uploading
            self.exportProgress = 1
            do {
                let record = try await RecordingShareService.shared.createLink(
                    artifact: artifact,
                    duration: duration)
                self.finishSharing()
                completion(.success(record))
            } catch {
                self.finishSharing()
                completion(.failure(Task.isCancelled ? .cancelled : .failed))
            }
        }
    }

    private func finishSharing() {
        isExporting = false
        exporter = nil
        shareTask = nil
    }

    func cancelExport() {
        exporter?.cancel()
        shareTask?.cancel()
    }
}

/// Owns the editor window. Same shape as the screenshot editor so the two
/// read as the same product: one dark surface, a band of actions at the top,
/// and the work in the middle.
final class RecorderEditorController: NSObject, NSWindowDelegate {
    private let model: RecorderEditorModel
    private var window: NSWindow?
    private var keyMonitor: Any?
    /// True once at least one file has been written from this recording. A
    /// recording that produced something can be closed without a question; one
    /// that produced nothing asks first, because closing throws it away.
    private var exported = false
    private var confirmedClose = false

    /// The recording this window owns, so the sweep can tell a folder somebody
    /// is still working in from one a crash left behind.
    var takeID: UUID { model.take.id }

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(L10n.shared.language)
    }

    private var shareStrings: RecorderShareStrings {
        FeatureStrings.recorderShare(L10n.shared.language)
    }

    init(take: RecorderTakeStore.Take) {
        model = RecorderEditorModel(take: take)
        super.init()
    }

    func show() {
        let content = RecorderEditorView(model: model, controller: self)
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        window.title = strings.editorTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Dark like every other picture editor, and like the sibling tool.
        window.appearance = NSAppearance(named: .darkAqua)
        // Dragging inside the window moves the trim handles, never the window.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        let visible = NSScreen.pointerVisibleFrame.size
        let width = min(max(1060, visible.width * 0.7), visible.width - 60)
        let height = min(max(600, visible.height * 0.68), visible.height - 80)
        window.setContentSize(CGSize(width: width.rounded(), height: height.rounded()))
        window.contentMinSize = CGSize(width: 940, height: 560)
        window.center()

        self.window = window
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    // MARK: - Actions

    func saveVideo() {
        let destination = ScreenRecorderService.saveDestination(strings: strings,
                                                                fileExtension: "mp4")
        run(.video, to: destination)
    }

    func saveGIF() {
        let destination = ScreenRecorderService.saveDestination(strings: strings,
                                                                fileExtension: "gif")
        run(.gif, to: destination)
    }

    func saveVideoAs() {
        guard let window else { return }
        let suggested = ScreenRecorderService.saveDestination(strings: strings,
                                                               fileExtension: "mp4")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.run(.video, to: url)
        }
    }

    func chooseSaveFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: DefaultsKey.recorderSaveFolder)
        }
    }

    func copyVideo() {
        copyVideoAndDelete(false)
    }

    func copyAndDelete() {
        copyVideoAndDelete(true)
    }

    func share(_ duration: RecordingShareDuration,
               completion: @escaping (RecordingShareRecord) -> Void) {
        model.share(duration) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(record):
                completion(record)
            case .failure(.cancelled):
                break
            case .failure(.tooLarge):
                NSSound.beep()
                QuickToolHUD.show(icon: "link", message: self.shareStrings.tooLarge)
            case .failure(.failed):
                NSSound.beep()
                QuickToolHUD.show(icon: "link", message: self.shareStrings.failed)
            }
        }
    }

    private func copyVideoAndDelete(_ deletesRecording: Bool) {
        guard let destination = copyDestination() else {
            QuickToolHUD.show(icon: "record.circle", message: strings.exportFailed)
            return
        }
        run(.video, to: destination, rememberDestination: false) { [weak self] url in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([url as NSURL]) else {
                NSSound.beep()
                QuickToolHUD.show(icon: "record.circle", message: self.strings.exportFailed)
                return
            }
            QuickToolHUD.show(icon: "doc.on.doc", message: self.strings.copiedHUD)
            if deletesRecording {
                self.confirmedClose = true
                self.window?.close()
            }
        }
    }

    func saveCurrentPreset() {
        guard let window else { return }
        let field = NSTextField(string: "")
        field.placeholderString = strings.presetNamePlaceholder
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert()
        alert.messageText = strings.savePreset
        alert.accessoryView = field
        alert.addButton(withTitle: strings.saveButton)
        alert.addButton(withTitle: strings.cancelButton)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.model.savePreset(named: field.stringValue)
        }
    }

    private func copyDestination() -> URL? {
        let manager = FileManager.default
        guard let base = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        let folder = base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Copied Recordings", isDirectory: true)
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else { return nil }
        if let files = try? manager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            for file in files where (try? file.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture < cutoff {
                try? manager.removeItem(at: file)
            }
        }
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix,
                                              date: Date(), fileExtension: "mp4")
        let unique = ScreenshotSupport.uniqueFileName(name) { candidate in
            manager.fileExists(atPath: folder.appendingPathComponent(candidate).path)
        }
        return folder.appendingPathComponent(unique)
    }

    private func run(_ output: RecorderExporter.Output,
                     to destination: URL,
                     rememberDestination: Bool = true,
                     onSuccess: ((URL) -> Void)? = nil) {
        model.export(output, to: destination, rememberDestination: rememberDestination) {
            [weak self] failure in
            guard let self else { return }
            switch failure {
            case nil:
                // The window stays: exports are slow and plural, and a person
                // who just made a video often wants the GIF of it too.
                self.exported = true
                RecentCaptureService.shared.recordRecording(at: destination)
                if let onSuccess {
                    onSuccess(destination)
                } else {
                    QuickToolHUD.show(
                        icon: "record.circle",
                        message: String(format: self.strings.savedHUDFormat,
                                        destination.deletingLastPathComponent().lastPathComponent))
                }
            case .cancelled:
                break
            case .tooLongForGIF:
                let seconds = Int(RecorderSupport.maximumGIFSeconds(
                    fps: self.model.document.resolvedGIFFrameRate))
                QuickToolHUD.show(icon: "record.circle",
                                  message: String(format: self.strings.gifTooLongFormat, seconds))
            default:
                NSSound.beep()
                QuickToolHUD.show(icon: "record.circle", message: self.strings.exportFailed)
            }
        }
    }

    /// Throwing the recording away, or closing a window that never produced a
    /// file, is the same act: the recording only exists here.
    func discard() {
        askBeforeLosingTheRecording { [weak self] in
            self?.confirmedClose = true
            self?.window?.close()
        }
    }

    private func askBeforeLosingTheRecording(_ confirmed: @escaping () -> Void) {
        guard let window else { return }
        model.pause()
        let alert = NSAlert()
        alert.messageText = strings.discardTitle
        alert.informativeText = exported ? strings.discardSavedMessage : strings.discardMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: strings.discardButton)
        alert.addButton(withTitle: strings.cancelButton)
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            confirmed()
        }
    }

    // MARK: - Window

    /// A recording that was never saved asks before it disappears. One that
    /// was saved closes straight away: the file it produced is what matters,
    /// and the master behind it has no life of its own.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isExporting {
            model.cancelExport()
        }
        guard !exported, !confirmedClose else { return true }
        askBeforeLosingTheRecording { [weak self] in
            self?.confirmedClose = true
            self?.window?.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        model.pause()
        model.cancelExport()
        // The recording lives exactly as long as its editor.
        RecorderTakeStore.shared.delete(model.take)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window = nil
        ScreenRecorderService.shared.editorDidClose(self)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow)
            else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let editsText = window.firstResponder is NSTextView
            if editsText,
               !(flags == .command && Int(event.keyCode) == kVK_ANSI_S),
               !(flags == [.command, .shift] && Int(event.keyCode) == kVK_ANSI_S) {
                return event
            }
            if flags == .command {
                switch Int(event.keyCode) {
                case kVK_ANSI_S:
                    self.saveVideo()
                    return nil
                case kVK_ANSI_Z:
                    self.model.undo()
                    return nil
                case kVK_ANSI_C:
                    self.copyVideo()
                    return nil
                default:
                    return event
                }
            }
            if flags == [.command, .shift], Int(event.keyCode) == kVK_ANSI_Z {
                self.model.redo()
                return nil
            }
            if flags == [.command, .shift], Int(event.keyCode) == kVK_ANSI_S {
                self.saveVideoAs()
                return nil
            }
            if flags == [.command, .option], Int(event.keyCode) == kVK_ANSI_C {
                self.copyAndDelete()
                return nil
            }
            guard flags.isEmpty else { return event }
            switch Int(event.keyCode) {
            case kVK_Space:
                self.model.togglePlay()
                return nil
            case kVK_Delete, kVK_ForwardDelete:
                // Delete means the thing that is selected, and only falls
                // through to throwing the whole recording away when nothing
                // is.
                if self.model.cutSelection != nil {
                    self.model.cutSelectedRange()
                    return nil
                }
                if self.model.selectedZoomID != nil {
                    self.model.removeSelectedZoom()
                    return nil
                }
                self.discard()
                return nil
            case kVK_Escape:
                if self.model.isExporting {
                    self.model.cancelExport()
                    return nil
                }
                if self.model.isAimingZoom {
                    self.model.isAimingZoom = false
                    return nil
                }
                if self.model.selectedZoomID != nil {
                    self.model.selectZoom(nil)
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }
}
