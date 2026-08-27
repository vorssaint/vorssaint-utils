// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct MediaSettings: View {
    var body: some View {
        MediaWorkspaceView(compact: false)
            .padding(16)
    }
}

struct PanelMediaView: View {
    var onClose: () -> Void

    var body: some View {
        MediaWorkspaceView(compact: true, onClose: onClose)
            .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
            .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }
}

private enum MediaCompressionLevel: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var quality: Double {
        switch self {
        case .low: return 0.88
        case .medium: return 0.68
        case .high: return 0.28
        }
    }

    var symbolName: String {
        switch self {
        case .low: return "circle"
        case .medium: return "circle.lefthalf.filled"
        case .high: return "circle.fill"
        }
    }

    static func nearest(to quality: Double) -> MediaCompressionLevel {
        allCases.min { abs($0.quality - quality) < abs($1.quality - quality) } ?? .medium
    }
}

struct MediaWorkspaceView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var media = MediaService.shared
    @ObservedObject private var featureRuntime = FeatureRuntime.shared
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(DefaultsKey.mediaLastTool) private var toolRaw = MediaTool.videoCompressor.rawValue
    @AppStorage(DefaultsKey.mediaVideoStart) private var videoStart = 0.0
    @AppStorage(DefaultsKey.mediaVideoEnd) private var videoEnd = 0.0
    @AppStorage(DefaultsKey.mediaVideoQuality) private var videoQuality = 0.68
    @AppStorage(DefaultsKey.mediaVideoMaxDimension) private var videoMaxDimension = 1280
    @AppStorage(DefaultsKey.mediaVideoSizing) private var videoSizingRaw = MediaSizingMode.resolution.rawValue
    @AppStorage(DefaultsKey.mediaVideoTargetMegabytes) private var videoTargetMegabytes = 20

    @AppStorage(DefaultsKey.mediaGIFStart) private var gifStart = 0.0
    @AppStorage(DefaultsKey.mediaGIFEnd) private var gifEnd = 0.0
    @AppStorage(DefaultsKey.mediaGIFWidth) private var gifWidth = 720
    @AppStorage(DefaultsKey.mediaGIFFPS) private var gifFPS = 12.0
    @AppStorage(DefaultsKey.mediaGIFLoops) private var gifLoops = true
    @AppStorage(DefaultsKey.mediaGIFSizing) private var gifSizingRaw = MediaSizingMode.resolution.rawValue
    @AppStorage(DefaultsKey.mediaGIFTargetMegabytes) private var gifTargetMegabytes = 10

    @AppStorage(DefaultsKey.mediaImageQuality) private var imageQuality = 0.72
    @AppStorage(DefaultsKey.mediaImageMaxDimension) private var imageMaxDimension = 1600
    @AppStorage(DefaultsKey.mediaImageFormat) private var imageFormatRaw = MediaImageFormat.jpeg.rawValue
    @AppStorage(DefaultsKey.mediaImageStripMetadata) private var imageStripMetadata = true
    @AppStorage(DefaultsKey.mediaImageResizeKind) private var imageResizeKindRaw = MediaImageResizeKind.maxDimension.rawValue
    @AppStorage(DefaultsKey.mediaImageResizeWidth) private var imageResizeWidth = 1600
    @AppStorage(DefaultsKey.mediaImageResizeHeight) private var imageResizeHeight = 1200
    @AppStorage(DefaultsKey.mediaImageExactResizeMode) private var imageExactResizeModeRaw = MediaImageExactResizeMode.stretch.rawValue
    @AppStorage(DefaultsKey.mediaImageWatermarkKind) private var imageWatermarkKindRaw = MediaImageWatermarkKind.off.rawValue
    @AppStorage(DefaultsKey.mediaImageWatermarkText) private var imageWatermarkText = ""
    @AppStorage(DefaultsKey.mediaImageWatermarkLogoPath) private var imageWatermarkLogoPath = ""
    @AppStorage(DefaultsKey.mediaImageWatermarkPosition) private var imageWatermarkPositionRaw = MediaImageWatermarkPosition.bottomRight.rawValue
    @AppStorage(DefaultsKey.mediaImageWatermarkOpacity) private var imageWatermarkOpacity = 0.45
    @AppStorage(DefaultsKey.mediaImageWatermarkMargin) private var imageWatermarkMargin = 32
    @AppStorage(DefaultsKey.mediaImageWatermarkScale) private var imageWatermarkScale = 0.18
    @AppStorage(DefaultsKey.mediaImageRenamePattern) private var imageRenamePattern = ""
    @AppStorage(DefaultsKey.mediaImageBackground) private var imageBackgroundRaw = MediaImageBackground.transparent.rawValue
    @AppStorage(DefaultsKey.mediaImagePreserveModificationDate) private var imagePreserveModificationDate = false
    @AppStorage(DefaultsKey.mediaImageProfiles) private var imageProfilesRaw = "[]"
    @AppStorage(DefaultsKey.mediaImageSelectedProfileID) private var imageSelectedProfileID = ""

    @AppStorage(DefaultsKey.mediaTextAccurate) private var textAccurate = true

    @State private var inputURLs: [URL] = []
    @State private var inputImageSize: CGSize?
    @State private var outputURL: URL?
    @State private var outputWasChosenManually = false
    @State private var isDropTargeted = false
    @State private var localMessage: String?
    @State private var mediaDefaultsTask: Task<Void, Never>?
    @State private var videoImportTask: Task<Void, Never>?
    @State private var videoImportGeneration = 0
    @State private var profileName = ""
    @State private var imageMoreOptionsExpanded = false
    @State private var isImportingVideo = false

    var compact: Bool
    var onClose: (() -> Void)? = nil

    private var inputURL: URL? { inputURLs.first }
    private var imageText: MediaImageConverterStrings {
        MediaImageConverterStrings.localized(l10n.language)
    }

    private var screenshotText: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var selectedTool: MediaTool {
        get { MediaSupport.sanitizedTool(toolRaw) }
        nonmutating set {
            cancelVideoImport()
            toolRaw = newValue.rawValue
            inputImageSize = newValue == .imageCompressor
                ? inputURL.flatMap { MediaSupport.imageDisplaySize(at: $0) }
                : nil
            outputURL = defaultOutputURL(for: inputURLs, tool: newValue)
            outputWasChosenManually = false
            applyMediaDefaults(for: inputURL, tool: newValue)
            localMessage = nil
            media.reset()
        }
    }

    private var selectedToolBinding: Binding<MediaTool> {
        Binding {
            selectedTool
        } set: { newValue in
            selectedTool = newValue
        }
    }

    private var isRunning: Bool {
        if case .running = media.state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            header
            toolPicker
            ScrollView {
                content
                    .padding(.trailing, 1)
            }
            .frame(maxHeight: compact ? 430 : .infinity)
        }
        .onChange(of: currentImageOptions) { oldOptions, newOptions in
            guard selectedTool == .imageCompressor else { return }
            if outputWasChosenManually {
                if inputURLs.count == 1,
                   oldOptions.format != newOptions.format,
                   let outputURL {
                    self.outputURL = MediaSupport.outputURLByReplacingExtension(
                        outputURL,
                        fileExtension: newOptions.format.fileExtension)
                }
                return
            }
            outputURL = defaultOutputURL(for: inputURLs, tool: .imageCompressor)
        }
        .onDisappear {
            mediaDefaultsTask?.cancel()
            cancelVideoImport()
        }
        .onChange(of: featureRuntime.revision) {
            if !AppFeature.mediaTools.isAvailable { cancelVideoImport() }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Label(l10n.s.mediaName, systemImage: "photo.on.rectangle.angled")
                .font(.system(size: compact ? 12 : 16, weight: .semibold))
            Spacer(minLength: 0)
            Text(l10n.s.mediaLocalNote)
                .font(.system(size: compact ? 9.5 : 11, weight: .medium))
                .foregroundStyle(.secondary)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(l10n.s.uninstallerCancel)
            }
        }
    }

    private var toolPicker: some View {
        Picker("", selection: selectedToolBinding) {
            ForEach(MediaTool.allCases) { tool in
                Text(title(for: tool)).tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            fileCard
            optionsCard
            actionRow
            statusCard
        }
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .trailing) {
                Button {
                    chooseInput()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: selectedTool == .textExtractor ? "doc.text.viewfinder" : "doc.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inputTitle)
                                .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(l10n.s.mediaDropHint)
                                .font(.system(size: compact ? 9.5 : 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(compact ? 9 : 12)
                    .padding(.trailing, inputURLs.isEmpty ? 0 : (compact ? 30 : 34))
                    .frame(maxWidth: .infinity, minHeight: compact ? 52 : 62, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: compact ? 52 : 62, alignment: .leading)

                if !inputURLs.isEmpty {
                    Button {
                        clearInput()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: compact ? 14 : 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.mediaCancel)
                    .padding(.trailing, compact ? 8 : 10)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 52 : 62, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.16) : PanelSurface.controlFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor.opacity(0.7) : PanelSurface.border(for: colorScheme),
                                  lineWidth: isDropTargeted ? 1.2 : 0.8)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                acceptDrop(providers)
            }

            HStack(spacing: 7) {
                Text(l10n.s.mediaOutput)
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(outputURL?.lastPathComponent ?? l10n.s.mediaOutputAutomatic)
                    .font(.system(size: compact ? 10 : 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button {
                    chooseOutput()
                } label: {
                    Label(l10n.s.mediaChooseOutput, systemImage: "folder")
                }
                .controlSize(.small)
                .disabled(inputURLs.isEmpty || isRunning)
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private var optionsCard: some View {
        switch selectedTool {
        case .videoCompressor:
            VStack(alignment: .leading, spacing: 10) {
                timeRangeRow(start: $videoStart, end: $videoEnd)
                sizingPicker(selection: $videoSizingRaw)
                if videoSizing == .resolution {
                    compressionRow(value: $videoQuality)
                    stepperInt(l10n.s.mediaMaxSize, value: $videoMaxDimension, range: 640...3840, step: 320, suffix: "px")
                } else {
                    targetSizeRow(value: $videoTargetMegabytes)
                }
            }
            .panelCard()
        case .gifMaker:
            VStack(alignment: .leading, spacing: 10) {
                timeRangeRow(start: $gifStart, end: $gifEnd)
                sizingPicker(selection: $gifSizingRaw)
                if gifSizing == .resolution {
                    fpsSliderRow(value: $gifFPS, range: 1...30)
                    HStack(spacing: 10) {
                        stepperInt(l10n.s.mediaWidth, value: $gifWidth, range: 160...1600, step: 80, suffix: "px")
                    }
                } else {
                    targetSizeRow(value: $gifTargetMegabytes)
                }
                Toggle(l10n.s.mediaLoopGIF, isOn: $gifLoops)
                    .toggleStyle(.checkbox)
            }
            .panelCard()
        case .imageCompressor:
            VStack(alignment: .leading, spacing: 10) {
                imageQuickPresetsRow
                imagePreviewSection
                Picker(l10n.s.mediaFormat, selection: $imageFormatRaw) {
                    Text("JPEG").tag(MediaImageFormat.jpeg.rawValue)
                    Text("PNG").tag(MediaImageFormat.png.rawValue)
                    Text("HEIC").tag(MediaImageFormat.heic.rawValue)
                    Text("PDF").tag(MediaImageFormat.pdf.rawValue)
                }
                .pickerStyle(.segmented)
                compressionRow(value: $imageQuality)
                imageResizeSection
                DisclosureHeaderRow(isExpanded: $imageMoreOptionsExpanded) {
                    Text(imageText.moreOptions)
                    Spacer()
                }
                if imageMoreOptionsExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        imageProfileRow
                        // PDF output never carries EXIF (the image is re-encoded
                        // into the document), so the toggle would be a dead control.
                        if MediaImageFormat.sanitized(imageFormatRaw) != .pdf {
                            Toggle(l10n.s.mediaStripMetadata, isOn: $imageStripMetadata)
                                .toggleStyle(.checkbox)
                        }
                        imageBackgroundSection
                        imageWatermarkSection
                        imageRenameSection
                        Toggle(imageText.preserveDate, isOn: $imagePreserveModificationDate)
                            .toggleStyle(.checkbox)
                    }
                    .padding(.top, 6)
                    .disclosureIndent()
                }
            }
            .panelCard()
        case .textExtractor:
            VStack(alignment: .leading, spacing: 10) {
                Picker(l10n.s.mediaOCRMode, selection: $textAccurate) {
                    Text(l10n.s.mediaOCRAccurate).tag(true)
                    Text(l10n.s.mediaOCRFast).tag(false)
                }
                .pickerStyle(.segmented)
            }
            .panelCard()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                run()
            } label: {
                Label(actionTitle, systemImage: selectedTool == .textExtractor ? "text.viewfinder" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputURLs.isEmpty || isRunning)

            if selectedTool == .videoCompressor {
                Button {
                    openVideoEditor()
                } label: {
                    Label(screenshotText.editButton, systemImage: "crop")
                }
                .disabled(inputURLs.count != 1 || isRunning || isImportingVideo)
                if isImportingVideo {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if isRunning {
                Button {
                    media.cancel()
                } label: {
                    Label(l10n.s.mediaCancel, systemImage: "xmark")
                }
            }

            Spacer(minLength: 0)
        }
        .controlSize(compact ? .small : .regular)
    }

    @ViewBuilder
    private var statusCard: some View {
        switch media.state {
        case .idle, .ready:
            if let localMessage {
                messageCard(localMessage, systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
        case let .running(progress, _):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(l10n.s.mediaRunning, systemImage: "gearshape.2")
                        .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
            }
            .panelCard()
        case let .completed(result):
            resultCard(result)
        case let .failed(failure):
            messageCard(message(for: failure), systemImage: "exclamationmark.triangle.fill", color: .orange)
        case .cancelled:
            messageCard(l10n.s.mediaCancelled, systemImage: "xmark.circle.fill", color: .secondary)
        }
    }

    private func resultCard(_ result: MediaResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l10n.s.mediaCompleted, systemImage: "checkmark.circle.fill")
                .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                .foregroundStyle(.green)
            if let outputURL = result.outputURL {
                Text(result.imageBatchItems.count > 1 ? batchSummary(result) : String(format: l10n.s.mediaResultSavedFormat, outputURL.lastPathComponent))
                    .font(.system(size: compact ? 10 : 11))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(String(format: l10n.s.mediaResultSizeFormat,
                            ByteCountFormatter.string(fromByteCount: result.originalBytes, countStyle: .file),
                            ByteCountFormatter.string(fromByteCount: result.outputBytes, countStyle: .file)))
                    .font(.system(size: compact ? 9.5 : 10.5))
                    .foregroundStyle(.secondary)
                if let delta = resultSizeDelta(result) {
                    Text(delta)
                        .font(.system(size: compact ? 9.5 : 10.5))
                        .foregroundStyle(.secondary)
                }
                if MediaSupport.outputGrew(originalBytes: result.originalBytes,
                                           outputBytes: result.outputBytes) {
                    Text(l10n.s.mediaResultGrewCaption)
                        .font(.system(size: compact ? 9.5 : 10.5))
                        .foregroundStyle(.secondary)
                }
                if result.failedCount > 0 {
                    Text(result.imageBatchItems.compactMap { item in
                        item.failure.map { "\(item.inputURL.lastPathComponent): \(message(for: $0))" }
                    }.prefix(3).joined(separator: "\n"))
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            if let text = result.text {
                Text(text.isEmpty ? l10n.s.mediaEmptyText : text)
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .lineLimit(compact ? 5 : 8)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.045)))
            }
            HStack(spacing: 8) {
                if let outputURL = result.outputURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(result.outputURLs.isEmpty ? [outputURL] : result.outputURLs)
                    } label: {
                        Label(l10n.s.mediaOpenInFinder, systemImage: "folder")
                    }
                }
                if let text = result.text {
                    Button {
                        copy(text)
                    } label: {
                        Label(l10n.s.mediaCopyText, systemImage: "doc.on.doc")
                    }
                }
                if result.imageBatchItems.count > 1 {
                    Button {
                        copy(batchSummaryText(result))
                    } label: {
                        Label(imageText.copySummary, systemImage: "doc.on.doc")
                    }
                }
                Button {
                    run()
                } label: {
                    Label(l10n.s.mediaRunAgain, systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.small)
        }
        .panelCard()
    }

    private func batchSummary(_ result: MediaResult) -> String {
        if result.failedCount > 0 {
            return String(format: imageText.batchPartialFormat, result.processedCount, result.failedCount)
        }
        return String(format: imageText.batchSavedFormat, result.processedCount)
    }

    private func batchSummaryText(_ result: MediaResult) -> String {
        var lines = [String(format: imageText.batchSummaryHeaderFormat, result.processedCount, result.failedCount)]
        if let delta = resultSizeDelta(result) {
            lines.append(delta)
        }
        for item in result.imageBatchItems {
            if let outputURL = item.outputURL {
                lines.append(String(format: imageText.batchSummaryItemFormat,
                                    item.inputURL.lastPathComponent,
                                    outputURL.lastPathComponent))
            } else if let failure = item.failure {
                lines.append("\(item.inputURL.lastPathComponent): \(message(for: failure))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func resultSizeDelta(_ result: MediaResult) -> String? {
        let delta = result.originalBytes - result.outputBytes
        guard delta != 0 else { return nil }
        let formatted = ByteCountFormatter.string(fromByteCount: abs(delta), countStyle: .file)
        if delta > 0 {
            return String(format: imageText.savedBytesFormat, formatted)
        }
        return String(format: imageText.grewBytesFormat, formatted)
    }

    private func messageCard(_ message: String, systemImage: String, color: Color) -> some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard()
    }

    private var imageProfileRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(imageText.profile, selection: $imageSelectedProfileID) {
                    Text(imageText.noProfile).tag("")
                    ForEach(imageProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .onChange(of: imageSelectedProfileID) { _, value in
                    guard !value.isEmpty,
                          let profile = imageProfiles.first(where: { $0.id == value }) else { return }
                    applyImageOptions(profile.options)
                }
                Button {
                    deleteSelectedProfile()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(imageSelectedProfileID.isEmpty)
                .help(imageText.deleteProfile)
            }
            if selectedImageProfile != nil, imageProfileIsModified {
                Label(imageText.profileModified, systemImage: "pencil")
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField(imageText.profileName, text: $profileName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    updateSelectedProfile()
                } label: {
                    Label(imageText.updateProfile, systemImage: "checkmark")
                }
                .controlSize(.small)
                .disabled(imageSelectedProfileID.isEmpty)
                Button {
                    saveNewProfile()
                } label: {
                    Label(imageText.saveAsNew, systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
    }

    private var imageQuickPresetsRow: some View {
        HStack(spacing: 6) {
            Button(imageText.presetWeb) {
                applyImageOptions(MediaImageOptions(quality: 0.72,
                                                    maxDimension: 1600,
                                                    format: .jpeg,
                                                    stripMetadata: true,
                                                    resizeMode: .maxDimension(1600),
                                                    renamePattern: MediaImageRenamePattern("{name}-web")))
            }
            Button(imageText.presetSocial) {
                applyImageOptions(MediaImageOptions(quality: 0.82,
                                                    maxDimension: 2048,
                                                    format: .png,
                                                    stripMetadata: true,
                                                    resizeMode: .maxDimension(2048),
                                                    renamePattern: MediaImageRenamePattern("{name}-social")))
            }
            Button(imageText.presetDocs) {
                applyImageOptions(MediaImageOptions(quality: 0.7,
                                                    maxDimension: 1600,
                                                    format: .pdf,
                                                    stripMetadata: true,
                                                    resizeMode: .maxDimension(1600),
                                                    background: .white,
                                                    preserveModificationDate: true))
            }
        }
        .controlSize(.small)
    }

    private var imagePreviewSection: some View {
        HStack(spacing: 10) {
            ZStack(alignment: previewAlignment) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(previewBackgroundColor)
                if let thumbnail = inputURL.flatMap({ ImageThumbnailer.thumbnail(for: $0, pointSize: compact ? 96 : 128) }) {
                    previewImage(thumbnail)
                        .padding(4)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: compact ? 26 : 32))
                        .foregroundStyle(.secondary)
                }
                previewWatermarkOverlay
                    .padding(previewWatermarkMargin)
                    .opacity(imageWatermarkOpacity)
            }
            .frame(width: previewFrameSize.width, height: previewFrameSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(imageText.preview)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                Text("\(imageText.outputName): \(previewOutputName)")
                    .font(.system(size: compact ? 9.5 : 10.5))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func previewImage(_ image: NSImage) -> some View {
        if currentResizeMode.kind == .exact, currentResizeMode.exactMode == .stretch {
            Image(nsImage: image)
                .resizable()
        } else if currentResizeMode.kind == .exact, currentResizeMode.exactMode == .fill {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder
    private var previewWatermarkOverlay: some View {
        if currentWatermark.isEnabled {
            HStack(spacing: 4) {
                if currentWatermark.usesLogo {
                    if let logo = NSImage(contentsOfFile: currentWatermark.logoPath) {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: previewWatermarkLogoSide, height: previewWatermarkLogoSide)
                    }
                }
                if currentWatermark.usesText {
                    Text(currentWatermark.text)
                        .font(.system(size: compact ? 8 : 10, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        }
    }

    private var imageResizeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker(imageText.resize, selection: $imageResizeKindRaw) {
                Text(imageText.resizeNone).tag(MediaImageResizeKind.none.rawValue)
                Text(imageText.resizeMax).tag(MediaImageResizeKind.maxDimension.rawValue)
                Text(imageText.resizeWidth).tag(MediaImageResizeKind.width.rawValue)
                Text(imageText.resizeHeight).tag(MediaImageResizeKind.height.rawValue)
                Text(imageText.resizeExact).tag(MediaImageResizeKind.exact.rawValue)
            }
            .pickerStyle(.menu)
            switch MediaImageResizeKind.sanitized(imageResizeKindRaw) {
            case .none:
                EmptyView()
            case .maxDimension:
                stepperInt(l10n.s.mediaMaxSize, value: $imageMaxDimension, range: 64...20_000, step: 128, suffix: "px")
            case .width:
                stepperInt(l10n.s.mediaWidth, value: $imageResizeWidth, range: 1...20_000, step: 64, suffix: "px")
            case .height:
                stepperInt(imageText.height, value: $imageResizeHeight, range: 1...20_000, step: 64, suffix: "px")
            case .exact:
                HStack(spacing: 10) {
                    stepperInt(l10n.s.mediaWidth, value: $imageResizeWidth, range: 1...20_000, step: 64, suffix: "px")
                    stepperInt(imageText.height, value: $imageResizeHeight, range: 1...20_000, step: 64, suffix: "px")
                }
                Picker("", selection: $imageExactResizeModeRaw) {
                    Text(imageText.exactStretch).tag(MediaImageExactResizeMode.stretch.rawValue)
                    Text(imageText.exactFit).tag(MediaImageExactResizeMode.fit.rawValue)
                    Text(imageText.exactFill).tag(MediaImageExactResizeMode.fill.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var imageWatermarkSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker(imageText.watermark, selection: $imageWatermarkKindRaw) {
                Text(imageText.watermarkOff).tag(MediaImageWatermarkKind.off.rawValue)
                Text(imageText.watermarkText).tag(MediaImageWatermarkKind.text.rawValue)
                Text(imageText.watermarkLogo).tag(MediaImageWatermarkKind.logo.rawValue)
                Text(imageText.watermarkBoth).tag(MediaImageWatermarkKind.textAndLogo.rawValue)
            }
            .pickerStyle(.menu)
            if currentWatermarkKind == .text || currentWatermarkKind == .textAndLogo {
                TextField(imageText.watermarkTextPlaceholder, text: $imageWatermarkText)
                    .textFieldStyle(.roundedBorder)
            }
            if currentWatermarkKind == .logo || currentWatermarkKind == .textAndLogo {
                HStack(spacing: 6) {
                    Text(imageWatermarkLogoPath.isEmpty ? imageText.noLogo : URL(fileURLWithPath: imageWatermarkLogoPath).lastPathComponent)
                        .font(.system(size: compact ? 10 : 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button {
                        chooseWatermarkLogo()
                    } label: {
                        Label(imageText.chooseLogo, systemImage: "photo")
                    }
                    .controlSize(.small)
                    if !imageWatermarkLogoPath.isEmpty {
                        Button {
                            imageWatermarkLogoPath = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if currentWatermarkKind != .off {
                Picker(imageText.position, selection: $imageWatermarkPositionRaw) {
                    Text(imageText.topLeft).tag(MediaImageWatermarkPosition.topLeft.rawValue)
                    Text(imageText.topRight).tag(MediaImageWatermarkPosition.topRight.rawValue)
                    Text(imageText.center).tag(MediaImageWatermarkPosition.center.rawValue)
                    Text(imageText.bottomLeft).tag(MediaImageWatermarkPosition.bottomLeft.rawValue)
                    Text(imageText.bottomRight).tag(MediaImageWatermarkPosition.bottomRight.rawValue)
                }
                .pickerStyle(.menu)
                stepperDouble(imageText.opacity, value: $imageWatermarkOpacity, range: 0.1...1, step: 0.05, suffix: "%") {
                    "\(Int(($0 * 100).rounded()))"
                }
                stepperInt(imageText.margin, value: $imageWatermarkMargin, range: 0...2000, step: 8, suffix: "px")
                stepperDouble(imageText.scale, value: $imageWatermarkScale, range: 0.05...0.8, step: 0.01, suffix: "%") {
                    "\(Int(($0 * 100).rounded()))"
                }
            }
        }
    }

    private var imageBackgroundSection: some View {
        Picker(imageText.background, selection: $imageBackgroundRaw) {
            Text(imageText.backgroundTransparent).tag(MediaImageBackground.transparent.rawValue)
            Text(imageText.backgroundWhite).tag(MediaImageBackground.white.rawValue)
            Text(imageText.backgroundBlack).tag(MediaImageBackground.black.rawValue)
        }
        .pickerStyle(.segmented)
    }

    private var imageRenameSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(imageText.rename)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            TextField("{name}-{index:03}", text: $imageRenamePattern)
                .textFieldStyle(.roundedBorder)
            Text("{name} {index} {index:03} {counter} {date} {time} {datetime} {width} {height} {format}")
                .font(.system(size: compact ? 8.5 : 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func timeRangeRow(start: Binding<Double>, end: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            numberField(l10n.s.mediaStartTime, value: start, suffix: "s")
            numberField(l10n.s.mediaEndTime, value: end, suffix: "s")
        }
    }

    private var videoSizing: MediaSizingMode {
        MediaSizingMode.sanitized(videoSizingRaw)
    }

    private var gifSizing: MediaSizingMode {
        MediaSizingMode.sanitized(gifSizingRaw)
    }

    private func sizingPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Text(l10n.s.mediaSizingResolution).tag(MediaSizingMode.resolution.rawValue)
            Text(l10n.s.mediaSizingFileSize).tag(MediaSizingMode.targetSize.rawValue)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func targetSizeRow(value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            integerField(l10n.s.mediaTargetSize,
                         value: value,
                         suffix: l10n.s.mediaMegabytesSuffix)
            Text(l10n.s.mediaTargetSizeHint)
                .font(.system(size: compact ? 9.5 : 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compressionRow(value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(l10n.s.mediaQuality)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            HStack(spacing: 6) {
                ForEach(MediaCompressionLevel.allCases) { level in
                    compressionButton(level, value: value)
                }
            }
        }
    }

    private func compressionButton(_ level: MediaCompressionLevel, value: Binding<Double>) -> some View {
        let selected = MediaCompressionLevel.nearest(to: value.wrappedValue) == level
        return Button {
            value.wrappedValue = level.quality
        } label: {
            HStack(spacing: 5) {
                Image(systemName: level.symbolName)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                Text(compressionTitle(for: level))
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 28 : 32)
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.78))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : PanelSurface.controlFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.45) : PanelSurface.border(for: colorScheme),
                                  lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func fpsSliderRow(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(l10n.s.mediaFPS)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    private func numberField(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        numberField(label, suffix: suffix) {
            TextField("", value: value, formatter: Self.decimalFormatter)
        }
    }

    private func integerField(_ label: String, value: Binding<Int>, suffix: String) -> some View {
        // Wider than the trim fields: this label is a phrase in most languages,
        // not a single word.
        numberField(label, suffix: suffix, labelWidth: compact ? 74 : 92) {
            TextField("", value: value, formatter: Self.megabytesFormatter)
        }
    }

    private func numberField<Field: View>(_ label: String,
                                          suffix: String,
                                          labelWidth: CGFloat? = nil,
                                          @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: labelWidth ?? (compact ? 48 : 62), alignment: .leading)
            field()
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 13 : 14, weight: .medium, design: .monospaced))
                .padding(.horizontal, 9)
                .frame(width: compact ? 62 : 76, height: compact ? 28 : 30, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PanelSurface.controlFill(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
                )
            Text(suffix)
                .font(.system(size: compact ? 9.5 : 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func stepperInt(_ label: String, value: Binding<Int>, range: ClosedRange<Int>,
                            step: Int, suffix: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(value.wrappedValue)\(suffix)")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepperDouble(_ label: String,
                               value: Binding<Double>,
                               range: ClosedRange<Double>,
                               step: Double,
                               suffix: String,
                               display: @escaping (Double) -> String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(display(value.wrappedValue))\(suffix)")
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputTitle: String {
        guard !inputURLs.isEmpty else { return l10n.s.mediaSelectFile }
        if selectedTool == .imageCompressor, inputURLs.count > 1 {
            return String(format: imageText.filesSelectedFormat, inputURLs.count)
        }
        return inputURLs[0].lastPathComponent
    }

    private var currentResizeMode: MediaImageResizeMode {
        MediaImageResizeMode(kind: MediaImageResizeKind.sanitized(imageResizeKindRaw),
                             maxDimension: imageMaxDimension,
                             width: imageResizeWidth,
                             height: imageResizeHeight,
                             exactMode: MediaImageExactResizeMode.sanitized(imageExactResizeModeRaw))
    }

    private var currentWatermarkKind: MediaImageWatermarkKind {
        MediaImageWatermarkKind.sanitized(imageWatermarkKindRaw)
    }

    private var currentWatermark: MediaImageWatermark {
        MediaImageWatermark(kind: currentWatermarkKind,
                            text: imageWatermarkText,
                            logoPath: imageWatermarkLogoPath,
                            position: MediaImageWatermarkPosition.sanitized(imageWatermarkPositionRaw),
                            opacity: imageWatermarkOpacity,
                            margin: imageWatermarkMargin,
                            scale: imageWatermarkScale)
    }

    private var currentImageOptions: MediaImageOptions {
        MediaImageOptions(quality: imageQuality,
                          maxDimension: imageMaxDimension,
                          format: MediaImageFormat.sanitized(imageFormatRaw),
                          stripMetadata: imageStripMetadata,
                          resizeMode: currentResizeMode,
                          watermark: currentWatermark,
                          renamePattern: MediaImageRenamePattern(imageRenamePattern),
                          background: MediaImageBackground.sanitized(imageBackgroundRaw),
                          preserveModificationDate: imagePreserveModificationDate)
    }

    private var imageProfiles: [MediaImageProfile] {
        guard let data = imageProfilesRaw.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([MediaImageProfile].self, from: data) else {
            return []
        }
        return MediaSupport.sanitizedImageProfiles(profiles)
    }

    private var selectedImageProfile: MediaImageProfile? {
        guard !imageSelectedProfileID.isEmpty else { return nil }
        return imageProfiles.first { $0.id == imageSelectedProfileID }
    }

    private var imageProfileIsModified: Bool {
        guard let profile = selectedImageProfile else { return false }
        return profile.options != currentImageOptions
    }

    private var previewOutputName: String {
        guard let inputURL else { return l10n.s.mediaOutputAutomatic }
        if let outputURL { return outputURL.lastPathComponent }
        return defaultOutputURL(for: [inputURL], tool: .imageCompressor)?.lastPathComponent
            ?? l10n.s.mediaOutputAutomatic
    }

    private var previewOutputSize: CGSize {
        guard inputURL != nil, let sourceSize = inputImageSize else {
            return currentResizeMode.targetSize(for: CGSize(width: 1600, height: 1200))
        }
        return currentResizeMode.targetSize(for: sourceSize)
    }

    private var previewFrameSize: CGSize {
        let bounds = CGSize(width: compact ? 108 : 136, height: compact ? 74 : 92)
        let ratio = max(0.01, previewOutputSize.width / previewOutputSize.height)
        if ratio > bounds.width / bounds.height {
            return CGSize(width: bounds.width, height: max(1, bounds.width / ratio))
        }
        return CGSize(width: max(1, bounds.height * ratio), height: bounds.height)
    }

    private var previewWatermarkLogoSide: CGFloat {
        let side = min(previewFrameSize.width, previewFrameSize.height)
        return min(side, max(4, side * CGFloat(currentWatermark.scale)))
    }

    private var previewWatermarkMargin: CGFloat {
        let outputSide = max(1, min(previewOutputSize.width, previewOutputSize.height))
        let previewSide = min(previewFrameSize.width, previewFrameSize.height)
        return min(previewSide / 2, CGFloat(imageWatermarkMargin) * previewSide / outputSide)
    }

    private var previewAlignment: Alignment {
        switch MediaImageWatermarkPosition.sanitized(imageWatermarkPositionRaw) {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .center: return .center
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    private var previewBackgroundColor: Color {
        if MediaImageFormat.sanitized(imageFormatRaw) == .jpeg
            || MediaImageFormat.sanitized(imageFormatRaw) == .pdf {
            return MediaImageBackground.sanitized(imageBackgroundRaw) == .black ? .black : .white
        }
        switch MediaImageBackground.sanitized(imageBackgroundRaw) {
        case .transparent:
            return Color.primary.opacity(0.045)
        case .white:
            return .white
        case .black:
            return .black
        }
    }

    private var actionTitle: String {
        switch selectedTool {
        case .videoCompressor: return l10n.s.mediaStartVideo
        case .gifMaker: return l10n.s.mediaStartGIF
        case .imageCompressor:
            // Choosing PDF changes the file's kind, so the button says what
            // will actually happen instead of promising compression.
            return MediaImageFormat.sanitized(imageFormatRaw) == .pdf
                ? l10n.s.mediaStartConvertPDF
                : l10n.s.mediaStartImage
        case .textExtractor: return l10n.s.mediaStartText
        }
    }

    private func title(for tool: MediaTool) -> String {
        switch tool {
        case .videoCompressor: return l10n.s.mediaToolVideo
        case .gifMaker: return l10n.s.mediaToolGIF
        case .imageCompressor: return l10n.s.mediaToolImage
        case .textExtractor: return l10n.s.mediaToolText
        }
    }

    private func compressionTitle(for level: MediaCompressionLevel) -> String {
        switch level {
        case .low: return l10n.s.mediaCompressionLow
        case .medium: return l10n.s.mediaCompressionMedium
        case .high: return l10n.s.mediaCompressionHigh
        }
    }

    private func chooseInput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = selectedTool == .imageCompressor
        panel.allowedContentTypes = inputTypes
        Self.runPanelModal(panel) { response in
            if response == .OK {
                setInputs(panel.urls)
            }
        }
    }

    private func chooseOutput() {
        guard let inputURL else { return }
        if selectedTool == .imageCompressor, inputURLs.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = (outputURL ?? inputURL.deletingLastPathComponent())
            Self.runPanelModal(panel) { response in
                if response == .OK, let url = panel.url {
                    outputURL = url
                    outputWasChosenManually = true
                }
            }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [outputType]
        let fallback = defaultOutputURL(for: inputURLs, tool: selectedTool)
        panel.directoryURL = (outputURL ?? fallback)?.deletingLastPathComponent()
        panel.nameFieldStringValue = (outputURL ?? fallback)?.lastPathComponent ?? ""
        Self.runPanelModal(panel) { response in
            if response == .OK, let url = panel.url {
                outputURL = url
                outputWasChosenManually = true
            }
        }
    }

    /// The hosts of this view (menu popover, quick launcher) never activate
    /// the app, and a modal file dialog in an inactive app takes no clicks or
    /// keys (only Cancel reacts). Activate first and let the run loop turn so
    /// the activation lands before the modal session starts, then hand key
    /// focus back to the launcher.
    /// One dialog at a time: the modal now starts a run-loop turn after the
    /// click, so a double-click (or clicking both pickers quickly) would queue
    /// a second identical dialog behind the first without this guard.
    private static var panelModalActive = false

    private static func runPanelModal(_ panel: NSSavePanel,
                                      completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard !panelModalActive else { return }
        panelModalActive = true
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let response = panel.runModal()
            panelModalActive = false
            QuickLauncherService.shared.refocusAfterModal()
            completion(response)
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else {
            return false
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var indexedURLs: [(offset: Int, url: URL)] = []
        for (offset, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let itemURL = item as? URL {
                url = itemURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
                if let url {
                    lock.lock()
                    indexedURLs.append((offset, url))
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = MediaSupport.urlsInProviderOrder(indexedURLs)
            let accepted = urls.filter { url in
                let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
                return MediaSupport.inputMatchesTool(contentType: contentType, inputTypes: inputTypes)
            }
            if accepted.isEmpty || (selectedTool != .imageCompressor && accepted.count != urls.count) {
                media.rejectUnsupportedInput()
            } else {
                setInputs(selectedTool == .imageCompressor ? accepted : Array(accepted.prefix(1)))
            }
        }
        return true
    }

    private func setInput(_ url: URL) {
        setInputs([url])
    }

    private func setInputs(_ urls: [URL]) {
        cancelVideoImport()
        inputURLs = selectedTool == .imageCompressor ? urls : Array(urls.prefix(1))
        inputImageSize = selectedTool == .imageCompressor
            ? inputURL.flatMap { MediaSupport.imageDisplaySize(at: $0) }
            : nil
        outputURL = defaultOutputURL(for: inputURLs, tool: selectedTool)
        outputWasChosenManually = false
        applyMediaDefaults(for: inputURL, tool: selectedTool)
        localMessage = nil
        media.reset()
    }

    private func clearInput() {
        mediaDefaultsTask?.cancel()
        cancelVideoImport()
        inputURLs = []
        inputImageSize = nil
        outputURL = nil
        outputWasChosenManually = false
        localMessage = nil
        media.reset()
    }

    private func applyMediaDefaults(for url: URL?, tool: MediaTool) {
        mediaDefaultsTask?.cancel()
        guard let url, tool == .videoCompressor || tool == .gifMaker else { return }
        mediaDefaultsTask = Task {
            guard let duration = await Self.mediaDuration(for: url),
                  !Task.isCancelled else { return }
            await MainActor.run {
                guard inputURL == url, selectedTool == tool else { return }
                switch tool {
                case .videoCompressor:
                    videoStart = 0
                    videoEnd = duration
                case .gifMaker:
                    gifStart = 0
                    gifEnd = duration
                case .imageCompressor, .textExtractor:
                    break
                }
            }
        }
    }

    private static func mediaDuration(for url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration).seconds else { return nil }
        guard duration.isFinite, duration > 0 else { return nil }
        return (duration * 10).rounded() / 10
    }

    @MainActor
    private func openVideoEditor() {
        guard AppFeature.mediaTools.isAvailable, let url = inputURL,
              !isImportingVideo else { return }
        cancelVideoImport()
        videoImportGeneration &+= 1
        let generation = videoImportGeneration
        isImportingVideo = true
        localMessage = nil
        videoImportTask = Task { @MainActor in
            let asset = AVURLAsset(url: url)
            let hasVideo = ((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false
            guard !Task.isCancelled, videoImportGeneration == generation,
                  inputURL == url, selectedTool == .videoCompressor,
                  AppFeature.mediaTools.isAvailable else { return }
            guard hasVideo else {
                isImportingVideo = false
                videoImportTask = nil
                localMessage = l10n.s.mediaErrorNoVideo
                return
            }
            let take = await Task.detached(priority: .userInitiated) {
                RecorderTakeStore.shared.importVideo(at: url)
            }.value
            guard !Task.isCancelled, videoImportGeneration == generation,
                  inputURL == url, selectedTool == .videoCompressor,
                  AppFeature.mediaTools.isAvailable else {
                if let take { RecorderTakeStore.shared.delete(take) }
                return
            }
            isImportingVideo = false
            videoImportTask = nil
            guard let take else {
                localMessage = l10n.s.mediaErrorUnsupported
                return
            }
            if !ScreenRecorderService.shared.openEditor(with: take, owner: .mediaTools) {
                RecorderTakeStore.shared.delete(take)
            }
        }
    }

    @MainActor
    private func cancelVideoImport() {
        videoImportGeneration &+= 1
        videoImportTask?.cancel()
        videoImportTask = nil
        isImportingVideo = false
    }

    private func run() {
        guard let inputURL, !inputURLs.isEmpty else {
            localMessage = l10n.s.mediaErrorNoFile
            return
        }
        let outputURL = outputURL ?? defaultOutputURL(for: inputURLs, tool: selectedTool)
        guard let outputURL else {
            localMessage = l10n.s.mediaErrorNoFile
            return
        }
        self.outputURL = outputURL
        localMessage = nil
        switch selectedTool {
        case .videoCompressor:
            media.compressVideo(inputURL: inputURL, outputURL: outputURL,
                                options: MediaVideoOptions(start: videoStart,
                                                           end: videoEnd,
                                                           quality: videoQuality,
                                                           maxDimension: videoMaxDimension,
                                                           fps: 30,
                                                           keepAudio: true,
                                                           codec: .h264,
                                                           sizing: videoSizing,
                                                           targetBytes: MediaSupport.targetBytes(
                                                               megabytes: videoTargetMegabytes)))
        case .gifMaker:
            media.makeGIF(inputURL: inputURL, outputURL: outputURL,
                          options: MediaGIFOptions(start: gifStart,
                                                   end: gifEnd,
                                                   quality: 0.74,
                                                   width: gifWidth,
                                                   fps: gifFPS,
                                                   loops: gifLoops,
                                                   sizing: gifSizing,
                                                   targetBytes: MediaSupport.targetBytes(
                                                       megabytes: gifTargetMegabytes)))
        case .imageCompressor:
            if inputURLs.count > 1 {
                media.processImages(inputURLs: inputURLs,
                                    outputDirectory: outputURL,
                                    options: currentImageOptions)
            } else {
                media.compressImage(inputURL: inputURL,
                                    outputURL: outputURL,
                                    options: currentImageOptions)
            }
        case .textExtractor:
            media.extractText(inputURL: inputURL, outputURL: outputURL,
                              options: MediaTextOptions(accurate: textAccurate,
                                                        languageCorrection: true,
                                                        recognitionLanguages: MediaSupport.recognitionLanguages(for: l10n.language.rawValue)))
        }
    }

    private var inputTypes: [UTType] {
        switch selectedTool {
        case .videoCompressor, .gifMaker:
            return [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        case .imageCompressor, .textExtractor:
            return [.image]
        }
    }

    private var outputType: UTType {
        switch selectedTool {
        case .videoCompressor: return .mpeg4Movie
        case .gifMaker: return .gif
        case .imageCompressor:
            switch MediaImageFormat.sanitized(imageFormatRaw) {
            case .jpeg: return .jpeg
            case .heic: return .heic
            case .png: return .png
            case .pdf: return .pdf
            }
        case .textExtractor: return .plainText
        }
    }

    private func defaultOutputURL(for inputURLs: [URL], tool: MediaTool) -> URL? {
        guard let inputURL = inputURLs.first else { return nil }
        switch tool {
        case .videoCompressor:
            return MediaSupport.uniqueOutputURL(for: inputURL, suffix: "-compressed", fileExtension: "mp4")
        case .gifMaker:
            return MediaSupport.uniqueOutputURL(for: inputURL, suffix: "", fileExtension: "gif")
        case .imageCompressor:
            if inputURLs.count > 1 {
                return inputURL.deletingLastPathComponent()
            }
            let sourceSize = inputImageSize ?? CGSize(width: 1600, height: 1200)
            return MediaSupport.imageOutputURL(for: inputURL,
                                               outputDirectory: inputURL.deletingLastPathComponent(),
                                               options: currentImageOptions,
                                               index: 1,
                                               outputSize: currentResizeMode.targetSize(for: sourceSize))
        case .textExtractor:
            return MediaSupport.uniqueOutputURL(for: inputURL, suffix: "-text", fileExtension: "txt")
        }
    }

    private func message(for failure: MediaFailure) -> String {
        switch failure {
        case .noInput: return l10n.s.mediaErrorNoFile
        case .noVideoTrack: return l10n.s.mediaErrorNoVideo
        case .sameOutput: return l10n.s.mediaErrorSameOutput
        case .unsupported: return l10n.s.mediaErrorUnsupported
        case .imageTooLarge: return imageText.tooLarge
        case let .gifTooLong(maxSeconds):
            return String(format: FeatureStrings.recorder(l10n.language).gifTooLongFormat,
                          maxSeconds)
        case .targetTooSmall: return l10n.s.mediaErrorTargetTooSmall
        case .watermarkUnavailable: return imageText.noLogo
        case .cancelled: return l10n.s.mediaCancelled
        case let .failed(message): return message.isEmpty ? l10n.s.mediaErrorUnsupported : message
        }
    }

    private func chooseWatermarkLogo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        Self.runPanelModal(panel) { response in
            if response == .OK, let url = panel.url {
                imageWatermarkLogoPath = url.path
            }
        }
    }

    private func updateSelectedProfile() {
        var profiles = imageProfiles
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imageSelectedProfileID.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == imageSelectedProfileID }) else { return }
        let name = trimmed.isEmpty ? profiles[index].name : trimmed
        profiles[index] = MediaImageProfile(id: profiles[index].id, name: name, options: currentImageOptions)
        profileName = ""
        saveImageProfiles(profiles)
    }

    private func saveNewProfile() {
        var profiles = imageProfiles
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? String(format: imageText.profileDefaultNameFormat, profiles.count + 1) : trimmed
        let profile = MediaImageProfile(name: name, options: currentImageOptions)
        profiles.append(profile)
        imageSelectedProfileID = profile.id
        profileName = ""
        saveImageProfiles(profiles)
    }

    private func deleteSelectedProfile() {
        guard !imageSelectedProfileID.isEmpty else { return }
        var profiles = imageProfiles
        profiles.removeAll { $0.id == imageSelectedProfileID }
        imageSelectedProfileID = ""
        saveImageProfiles(profiles)
    }

    private func saveImageProfiles(_ profiles: [MediaImageProfile]) {
        let cleanProfiles = MediaSupport.sanitizedImageProfiles(profiles)
        guard let data = try? JSONEncoder().encode(cleanProfiles),
              let raw = String(data: data, encoding: .utf8) else { return }
        imageProfilesRaw = raw
    }

    private func applyImageOptions(_ options: MediaImageOptions) {
        imageQuality = options.quality
        // Older profiles can carry the previously clamped legacy field;
        // resizeMode remains authoritative for the value the user selected.
        imageMaxDimension = options.resizeMode.maxDimension
        imageFormatRaw = options.format.rawValue
        imageStripMetadata = options.stripMetadata
        imageResizeKindRaw = options.resizeMode.kind.rawValue
        imageResizeWidth = options.resizeMode.width
        imageResizeHeight = options.resizeMode.height
        imageExactResizeModeRaw = options.resizeMode.exactMode.rawValue
        imageWatermarkKindRaw = options.watermark.kind.rawValue
        imageWatermarkText = options.watermark.text
        imageWatermarkLogoPath = options.watermark.logoPath
        imageWatermarkPositionRaw = options.watermark.position.rawValue
        imageWatermarkOpacity = options.watermark.opacity
        imageWatermarkMargin = options.watermark.margin
        imageWatermarkScale = options.watermark.scale
        imageRenamePattern = options.renamePattern.rawValue
        imageBackgroundRaw = options.background.rawValue
        imagePreserveModificationDate = options.preserveModificationDate
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// A size target is typed rather than stepped, so the formatter is what
    /// keeps it a whole number the planner can work with.
    private static let megabytesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: MediaSupport.minimumTargetMegabytes)
        formatter.maximum = NSNumber(value: MediaSupport.maximumTargetMegabytes)
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = 0
        return formatter
    }()
}
