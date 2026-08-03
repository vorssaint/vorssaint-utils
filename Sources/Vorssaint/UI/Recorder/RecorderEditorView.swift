// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AVKit
import SwiftUI

/// The recording editor. Real bands, not floating chrome: the picture lives
/// in its own region and nothing ever slides underneath the controls.
struct RecorderEditorView: View {
    @ObservedObject var model: RecorderEditorModel
    let controller: RecorderEditorController
    @ObservedObject private var l10n = L10n.shared

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBand
            HStack(spacing: 0) {
                stage
                Divider().opacity(0.5)
                RecorderInspector(model: model)
            }
            bottomBand
        }
        .background(stageBackground)
        // The window shows its content under the title bar, and SwiftUI insets
        // for that bar by default. Taking the inset back is what lets the top
        // band BE the title bar, with the brand and the actions on the same
        // line as the traffic lights instead of a band's height below them.
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeOut(duration: 0.18), value: model.isExporting)
        .animation(.easeOut(duration: 0.18), value: model.lastExportedURL)
        .frame(minWidth: 940, minHeight: 560)
    }

    // MARK: - Bands

    private var topBand: some View {
        HStack(spacing: 8) {
            BrandMark(width: 24, tint: Color(white: 0.92))
            Text(strings.editorTitle)
                .font(.system(size: 13, weight: .semibold))
            Divider().frame(height: 18).padding(.horizontal, 3)
            Button(action: model.undo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(RecorderToolbarButtonStyle(compact: true))
            .disabled(!model.canUndo)
            .screenshotSafeHelp("⌘Z")
            Button(action: model.redo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(RecorderToolbarButtonStyle(compact: true))
            .disabled(!model.canRedo)
            .screenshotSafeHelp("⇧⌘Z")
            presetsMenu

            Spacer(minLength: 10)
            if let url = model.lastExportedURL, !model.isExporting {
                finishedFileChip(url)
            }
            if model.isExporting {
                exportProgressChip
            }
            HStack(spacing: 5) {
                Button(action: controller.discard) {
                    Image(systemName: "trash")
                }
                .buttonStyle(RecorderToolbarButtonStyle(compact: true, destructive: true))
                .screenshotSafeHelp(strings.discardButton)
                .accessibilityLabel(strings.discardButton)

                Button(action: controller.copyAndDelete) {
                    Label(strings.copyAndDeleteButton, systemImage: "doc.on.doc")
                }
                .buttonStyle(RecorderToolbarButtonStyle())
                .disabled(model.isExporting)
                .screenshotSafeHelp("⌥⌘C")
                Button(action: controller.copyVideo) {
                    Label(strings.copyButton, systemImage: "doc.on.doc")
                }
                .buttonStyle(RecorderToolbarButtonStyle())
                .disabled(model.isExporting)
                .screenshotSafeHelp("⌘C")
            }

            Menu {
                Button(strings.saveVideoButton, action: controller.saveVideo)
                    .keyboardShortcut("s", modifiers: .command)
                Button(strings.saveAsButton, action: controller.saveVideoAs)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button(strings.saveGIFButton, action: controller.saveGIF)
                Divider()
                Button(strings.folderLabel + "…", action: controller.chooseSaveFolder)
            } label: {
                Label(strings.saveVideoButton, systemImage: "square.and.arrow.down")
            } primaryAction: {
                controller.saveVideo()
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .disabled(model.isExporting)
            .screenshotSafeHelp("⌘S")
        }
        .padding(.leading, 76)
        .padding(.trailing, 14)
        .frame(height: 54)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var presetsMenu: some View {
        Menu {
            Button(strings.lookRaw) { model.applyLook(.raw) }
            Button(strings.lookClean) { model.applyLook(.clean) }
            Button(strings.lookStudio) { model.applyLook(.studio) }
            if !model.editPresets.isEmpty {
                Divider()
                ForEach(model.editPresets) { preset in
                    Button(preset.name) { model.applyPreset(preset) }
                }
                Menu(strings.removePreset) {
                    ForEach(model.editPresets) { preset in
                        Button(preset.name) { model.removePreset(preset) }
                    }
                }
            }
            Divider()
            Button(strings.savePreset, action: controller.saveCurrentPreset)
        } label: {
            Label(strings.presetsButton, systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(Color.white.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var stage: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.72))
                PlayerSurface(player: model.player)
                if model.isAimingZoom {
                    // Aiming is a single click on the picture, and the overlay
                    // is what says so: the pointer becomes a crosshair and the
                    // next click is the aim.
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            model.aim(at: location, in: proxy.size)
                        }
                    VStack {
                        Text(strings.zoomPickSpotHint)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.regularMaterial,
                                        in: Capsule())
                            .padding(.top, 10)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .onTapGesture {
            guard !model.isAimingZoom else { return }
            // Clicking the picture puts a selected zoom down before it does
            // anything else, so there is always a way out of it.
            if model.selectedZoomID != nil {
                model.selectZoom(nil)
            } else {
                model.togglePlay()
            }
        }
    }

    private var bottomBand: some View {
        VStack(spacing: 6) {
            transportRow
                .padding(.bottom, 4)
            timelineRow(strings.zoomSectionLabel) {
                VStack(spacing: 2) {
                    ClickRuler(model: model).frame(height: 12)
                    RecorderZoomLane(model: model, kind: .zoom,
                                     emptyHint: strings.zoomLaneEmptyHint)
                        .frame(height: 30)
                }
            }
            // The text lane only exists once there is text, so an editor
            // nobody typed in stays as simple as it was.
            if !model.document.texts.isEmpty {
                timelineRow(strings.textContentLabel) {
                    RecorderZoomLane(model: model, kind: .text,
                                     emptyHint: strings.textLaneEmptyHint)
                        .frame(height: 30)
                }
            }
            timelineRow(strings.editorTitle) {
                Filmstrip(model: model).frame(height: 54)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    private func timelineRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
                .lineLimit(1)
            content()
        }
    }

    private var transportRow: some View {
        HStack(spacing: 12) {
            Button(action: model.togglePlay) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .screenshotSafeHelp("Space")

            Text(timeLabel)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.78))

            Button {
                model.addText(at: model.sourceTime)
            } label: {
                Label(strings.addTextButton, systemImage: "textformat")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(white: 0.8))

            if let selection = model.cutSelection {
                Button {
                    model.cutSelectedRange()
                } label: {
                    Label(strings.cutOutButton + "  "
                          + RecorderSupport.elapsedLabel(
                            seconds: Int((selection.upperBound - selection.lowerBound).rounded())),
                          systemImage: "scissors")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.red)
                .disabled(!model.canCutSelection)
            }

            Spacer()

            Button(action: model.toggleSound) {
                Image(systemName: model.document.keepsSystemAudio
                      ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(model.document.keepsSystemAudio ? .accentColor : nil)
            .screenshotSafeHelp(strings.systemAudioToggle)
            .accessibilityLabel(strings.systemAudioToggle)

            Menu {
                Picker(strings.qualityLabel, selection: qualityBinding) {
                    Text(strings.qualitySmall).tag(RecorderSupport.Quality.small.rawValue)
                    Text(strings.qualityBalanced).tag(RecorderSupport.Quality.balanced.rawValue)
                    Text(strings.qualityHigh).tag(RecorderSupport.Quality.high.rawValue)
                }
                .pickerStyle(.inline)
            } label: {
                Label(qualityTitle + "  " + outputSizeLabel, systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .screenshotSafeHelp(strings.qualityLabel)
        }
    }

    private var qualityBinding: Binding<String> {
        Binding(get: { model.document.quality },
                set: { value in
                    var next = model.document
                    next.quality = value
                    model.document = next
                })
    }

    private var qualityTitle: String {
        switch model.document.resolvedQuality {
        case .small: return strings.qualitySmall
        case .balanced: return strings.qualityBalanced
        case .high: return strings.qualityHigh
        }
    }

    /// What this preset actually produces for THIS recording. A file size
    /// would be a guess, because a bitrate is a ceiling and screen content
    /// undershoots it hard; the resolution is a fact.
    private var outputSizeLabel: String {
        let size = model.exportSize
        guard size.width > 0 else { return "" }
        return "\(Int(size.width))x\(Int(size.height))"
    }

    private var timeLabel: String {
        RecorderSupport.elapsedLabel(seconds: Int(model.currentTime))
            + " / "
            + RecorderSupport.elapsedLabel(seconds: Int(model.outputDuration.rounded()))
    }

    // MARK: - Surfaces

    private var stageBackground: some View {
        Rectangle()
            .fill(Color(white: 0.115))
            .overlay {
                LinearGradient(colors: [Color.white.opacity(0.035), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
    }

    /// Saving keeps the picture visible: a scrim over the whole editor says
    /// "this is hard for me", and it is not.
    private var exportProgressChip: some View {
        HStack(spacing: 8) {
            ProgressView(value: model.exportProgress)
                .progressViewStyle(.linear)
                .frame(width: 110)
            Text(strings.exportingLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.8))
            Button(strings.cancelButton) { model.cancelExport() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .transition(.opacity)
    }

    /// The finished file itself, draggable straight into a chat window and
    /// clickable to show it in the Finder. Ending with the name of a folder
    /// stops one step short of what the person actually wanted.
    private func finishedFileChip(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 190)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .screenshotSafeHelp(l10n.s.cleanerRevealInFinder)
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .transition(.opacity)
    }
}

private struct RecorderToolbarButtonStyle: ButtonStyle {
    var compact = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, compact ? 0 : 10)
            .frame(width: compact ? 30 : nil, height: 30)
            .background(Color.white.opacity(configuration.isPressed ? 0.11 : 0.055),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.15 : 0.08),
                                  lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Player

/// A plain player layer. SwiftUI's own player brings system transport
/// controls with it, and the editor already has its own.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = LayerBackedPlayerView()
        view.wantsLayer = true
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? LayerBackedPlayerView)?.playerLayer.player = player
    }

    final class LayerBackedPlayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            layer = playerLayer
            layerContentsRedrawPolicy = .duringViewResize
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}

// MARK: - Filmstrip

/// The recording as a strip of frames, with the kept part bright and a handle
/// at each end. Dragging a handle is the whole trim interaction: there is no
/// second place to type numbers, because there does not need to be.
private struct Filmstrip: View {
    @ObservedObject var model: RecorderEditorModel
    private enum Handle { case start, end }

    private let handleWidth: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let trim = model.trim
            let startX = position(trim.start, width: width)
            let endX = max(startX + handleWidth * 2, position(trim.end, width: width))

            ZStack(alignment: .topLeading) {
                // The strip itself is what scrubbing listens to. The handles
                // sit above it with their own gestures, so a drag that starts
                // on a handle trims and never moves the playhead too.
                // Dragging across the film picks a stretch to remove; a plain
                // click clears it. Scrubbing lives on the ruler above, so the
                // two never fight over the same drag.
                thumbnails
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                let from = seconds(at: value.startLocation.x, width: width)
                                let to = seconds(at: value.location.x, width: width)
                                model.setCutSelection(min(from, to)...max(from, to))
                            }
                    )
                    .onTapGesture { location in
                        if model.cutSelection != nil {
                            model.setCutSelection(nil)
                        } else {
                            model.seek(to: seconds(at: location.x, width: width))
                        }
                    }

                // What was already cut out, as a seam you can click to undo.
                ForEach(Array(model.document.cuts.enumerated()), id: \.offset) { _, cut in
                    let seam = position(cut.start, width: width)
                    Rectangle()
                        .fill(Color.orange.opacity(0.9))
                        .frame(width: 3, height: height)
                        .offset(x: max(0, seam - 1.5))
                        .onTapGesture { model.restoreCut(at: cut.start) }
                }

                if let selection = model.cutSelection {
                    let from = position(selection.lowerBound, width: width)
                    let to = position(selection.upperBound, width: width)
                    Rectangle()
                        .fill(Color.red.opacity(0.28))
                        .frame(width: max(1, to - from), height: height)
                        .overlay {
                            Rectangle().strokeBorder(Color.red.opacity(0.9), lineWidth: 1.5)
                        }
                        .offset(x: from)
                        .allowsHitTesting(false)
                }

                Color.black.opacity(0.62)
                    .frame(width: max(0, startX))
                    .allowsHitTesting(false)
                Color.black.opacity(0.62)
                    .frame(width: max(0, width - endX))
                    .offset(x: endX)
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 2)
                    .frame(width: endX - startX)
                    .offset(x: startX)
                    .allowsHitTesting(false)

                handle(at: startX, height: height)
                    .gesture(drag(.start, width: width))
                handle(at: endX - handleWidth, height: height)
                    .gesture(drag(.end, width: width))

                playhead(at: position(model.sourceTime, width: width), height: height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var thumbnails: some View {
        HStack(spacing: 0) {
            if model.thumbnails.isEmpty {
                Rectangle().fill(Color(white: 0.18))
            } else {
                ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
    }

    private func handle(at x: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: height * 0.36)
            }
            .offset(x: max(0, x))
            .contentShape(Rectangle().inset(by: -6))
    }

    private func playhead(at x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: height)
            .shadow(color: .black.opacity(0.6), radius: 1)
            .offset(x: max(0, x - 1))
            .allowsHitTesting(false)
    }

    private func drag(_ handle: Handle, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let time = seconds(at: value.location.x, width: width)
                switch handle {
                case .start: model.setTrimStart(time)
                case .end: model.setTrimEnd(time)
                }
            }
    }

    private func position(_ seconds: Double, width: CGFloat) -> CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, seconds / model.duration))) * width
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(max(0, min(1, x / width))) * model.duration
    }
}

// MARK: - Ruler

/// A tick for every press the recording captured. It costs almost nothing,
/// it gives the zooms something to snap onto, and it silently answers the
/// first question anybody asks about an automatic zoom: why is it here.
private struct ClickRuler: View {
    @ObservedObject var model: RecorderEditorModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = max(0.001, model.duration)
            ZStack(alignment: .topLeading) {
                // The ruler is where scrubbing lives, so the filmstrip below
                // is free to be about picking a stretch to cut.
                Color.black.opacity(0.001)
                    .frame(width: width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.seek(to: Double(min(1, max(0, value.location.x / width)))
                                            * duration)
                            }
                    )
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .offset(y: proxy.size.height - 1)
                ForEach(Array(model.pointerTrack.clicks.filter(\.isDown).enumerated()),
                        id: \.offset) { _, click in
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1.5, height: 7)
                        .offset(x: CGFloat(min(1, max(0, click.time / duration))) * width,
                                y: proxy.size.height - 8)
                }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: proxy.size.height)
                    .offset(x: CGFloat(min(1, max(0, model.sourceTime / duration))) * width - 1)
            }
        }
    }
}
