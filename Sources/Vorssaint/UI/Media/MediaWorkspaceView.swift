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
            .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
            .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
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
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(DefaultsKey.mediaLastTool) private var toolRaw = MediaTool.videoCompressor.rawValue
    @AppStorage(DefaultsKey.mediaVideoStart) private var videoStart = 0.0
    @AppStorage(DefaultsKey.mediaVideoEnd) private var videoEnd = 0.0
    @AppStorage(DefaultsKey.mediaVideoQuality) private var videoQuality = 0.68
    @AppStorage(DefaultsKey.mediaVideoMaxDimension) private var videoMaxDimension = 1280

    @AppStorage(DefaultsKey.mediaGIFStart) private var gifStart = 0.0
    @AppStorage(DefaultsKey.mediaGIFEnd) private var gifEnd = 0.0
    @AppStorage(DefaultsKey.mediaGIFWidth) private var gifWidth = 720
    @AppStorage(DefaultsKey.mediaGIFFPS) private var gifFPS = 12.0
    @AppStorage(DefaultsKey.mediaGIFLoops) private var gifLoops = true

    @AppStorage(DefaultsKey.mediaImageQuality) private var imageQuality = 0.72
    @AppStorage(DefaultsKey.mediaImageMaxDimension) private var imageMaxDimension = 1600
    @AppStorage(DefaultsKey.mediaImageFormat) private var imageFormatRaw = MediaImageFormat.jpeg.rawValue
    @AppStorage(DefaultsKey.mediaImageStripMetadata) private var imageStripMetadata = true

    @AppStorage(DefaultsKey.mediaTextAccurate) private var textAccurate = true

    @State private var inputURL: URL?
    @State private var outputURL: URL?
    @State private var outputWasChosenManually = false
    @State private var isDropTargeted = false
    @State private var localMessage: String?
    @State private var mediaDefaultsTask: Task<Void, Never>?

    var compact: Bool
    var onClose: (() -> Void)? = nil

    private var selectedTool: MediaTool {
        get { MediaSupport.sanitizedTool(toolRaw) }
        nonmutating set {
            toolRaw = newValue.rawValue
            outputURL = defaultOutputURL(for: inputURL, tool: newValue)
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
            if compact {
                ScrollView {
                    content
                        .padding(.trailing, 1)
                }
                .frame(maxHeight: 430)
            } else {
                content
            }
        }
        .onChange(of: imageFormatRaw) { _, _ in
            guard selectedTool == .imageCompressor, !outputWasChosenManually else { return }
            outputURL = defaultOutputURL(for: inputURL, tool: .imageCompressor)
        }
        .onDisappear {
            mediaDefaultsTask?.cancel()
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
                            Text(inputURL?.lastPathComponent ?? l10n.s.mediaSelectFile)
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
                    .padding(.trailing, inputURL == nil ? 0 : (compact ? 30 : 34))
                    .frame(maxWidth: .infinity, minHeight: compact ? 52 : 62, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: compact ? 52 : 62, alignment: .leading)

                if inputURL != nil {
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
                .disabled(inputURL == nil || isRunning)
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
                compressionRow(value: $videoQuality)
                stepperInt(l10n.s.mediaMaxSize, value: $videoMaxDimension, range: 640...3840, step: 320, suffix: "px")
            }
            .panelCard()
        case .gifMaker:
            VStack(alignment: .leading, spacing: 10) {
                timeRangeRow(start: $gifStart, end: $gifEnd)
                fpsSliderRow(value: $gifFPS, range: 1...30)
                HStack(spacing: 10) {
                    stepperInt(l10n.s.mediaWidth, value: $gifWidth, range: 160...1600, step: 80, suffix: "px")
                }
                Toggle(l10n.s.mediaLoopGIF, isOn: $gifLoops)
                    .toggleStyle(.checkbox)
            }
            .panelCard()
        case .imageCompressor:
            VStack(alignment: .leading, spacing: 10) {
                Picker(l10n.s.mediaFormat, selection: $imageFormatRaw) {
                    Text("JPEG").tag(MediaImageFormat.jpeg.rawValue)
                    Text("HEIC").tag(MediaImageFormat.heic.rawValue)
                    Text("PNG").tag(MediaImageFormat.png.rawValue)
                }
                .pickerStyle(.segmented)
                compressionRow(value: $imageQuality)
                stepperInt(l10n.s.mediaMaxSize, value: $imageMaxDimension, range: 256...7680, step: 128, suffix: "px")
                Toggle(l10n.s.mediaStripMetadata, isOn: $imageStripMetadata)
                    .toggleStyle(.checkbox)
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
            .disabled(inputURL == nil || isRunning)

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
                Text(String(format: l10n.s.mediaResultSavedFormat, outputURL.lastPathComponent))
                    .font(.system(size: compact ? 10 : 11))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(String(format: l10n.s.mediaResultSizeFormat,
                            ByteCountFormatter.string(fromByteCount: result.originalBytes, countStyle: .file),
                            ByteCountFormatter.string(fromByteCount: result.outputBytes, countStyle: .file)))
                    .font(.system(size: compact ? 9.5 : 10.5))
                    .foregroundStyle(.secondary)
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
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
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

    private func messageCard(_ message: String, systemImage: String, color: Color) -> some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard()
    }

    private func timeRangeRow(start: Binding<Double>, end: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            numberField(l10n.s.mediaStartTime, value: start, suffix: "s")
            numberField(l10n.s.mediaEndTime, value: end, suffix: "s")
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
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .frame(width: compact ? 48 : 62, alignment: .leading)
            TextField("", value: value, formatter: Self.decimalFormatter)
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

    private var actionTitle: String {
        switch selectedTool {
        case .videoCompressor: return l10n.s.mediaStartVideo
        case .gifMaker: return l10n.s.mediaStartGIF
        case .imageCompressor: return l10n.s.mediaStartImage
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
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = inputTypes
        if panel.runModal() == .OK, let url = panel.url {
            setInput(url)
        }
    }

    private func chooseOutput() {
        guard let inputURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [outputType]
        let fallback = defaultOutputURL(for: inputURL, tool: selectedTool)
        panel.directoryURL = (outputURL ?? fallback)?.deletingLastPathComponent()
        panel.nameFieldStringValue = (outputURL ?? fallback)?.lastPathComponent ?? ""
        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
            outputWasChosenManually = true
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
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
                DispatchQueue.main.async { setInput(url) }
            }
        }
        return true
    }

    private func setInput(_ url: URL) {
        inputURL = url
        outputURL = defaultOutputURL(for: url, tool: selectedTool)
        outputWasChosenManually = false
        applyMediaDefaults(for: url, tool: selectedTool)
        localMessage = nil
        media.reset()
    }

    private func clearInput() {
        mediaDefaultsTask?.cancel()
        inputURL = nil
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

    private func run() {
        guard let inputURL else {
            localMessage = l10n.s.mediaErrorNoFile
            return
        }
        let outputURL = outputURL ?? defaultOutputURL(for: inputURL, tool: selectedTool)
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
                                                           codec: .h264))
        case .gifMaker:
            media.makeGIF(inputURL: inputURL, outputURL: outputURL,
                          options: MediaGIFOptions(start: gifStart,
                                                   end: gifEnd,
                                                   quality: 0.74,
                                                   width: gifWidth,
                                                   fps: gifFPS,
                                                   loops: gifLoops))
        case .imageCompressor:
            media.compressImage(inputURL: inputURL, outputURL: outputURL,
                                options: MediaImageOptions(quality: imageQuality,
                                                           maxDimension: imageMaxDimension,
                                                           format: MediaImageFormat.sanitized(imageFormatRaw),
                                                           stripMetadata: imageStripMetadata))
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
            }
        case .textExtractor: return .plainText
        }
    }

    private func defaultOutputURL(for inputURL: URL?, tool: MediaTool) -> URL? {
        guard let inputURL else { return nil }
        switch tool {
        case .videoCompressor:
            return MediaSupport.uniqueOutputURL(for: inputURL, suffix: "-compressed", fileExtension: "mp4")
        case .gifMaker:
            return MediaSupport.uniqueOutputURL(for: inputURL, suffix: "", fileExtension: "gif")
        case .imageCompressor:
            return MediaSupport.uniqueOutputURL(for: inputURL, suffix: "-compressed",
                                                fileExtension: MediaImageFormat.sanitized(imageFormatRaw).fileExtension)
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
        case .cancelled: return l10n.s.mediaCancelled
        case let .failed(message): return message.isEmpty ? l10n.s.mediaErrorUnsupported : message
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = 0
        return formatter
    }()
}
