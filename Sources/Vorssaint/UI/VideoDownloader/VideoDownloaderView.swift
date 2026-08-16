// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import Combine
import Foundation
import ImageIO
#if !VORSSAINT_TEST
import SwiftUI
#endif

final class VideoDownloaderThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private let url: URL
    private let endpointValidator: (URL) -> Bool
    private let configurationProvider: () -> URLSessionConfiguration
    private let stateLock = NSLock()
    private var fetcher: VideoDownloaderImageFetcher?
    private var generation = UUID()

    init(url: URL,
         endpointValidator: @escaping (URL) -> Bool = {
             VideoDownloaderThumbnailURLPolicy.resolvesToPublicEndpoint($0)
         },
         configurationProvider: @escaping () -> URLSessionConfiguration = {
             URLSessionConfiguration.ephemeral
         }) {
        self.url = url
        self.endpointValidator = endpointValidator
        self.configurationProvider = configurationProvider
    }

    func load() {
        cancel()
        let loadGeneration = UUID()
        let fetcher = VideoDownloaderImageFetcher(url: url,
                                                   timeout: 8,
                                                   endpointValidator: endpointValidator,
                                                   configurationProvider: configurationProvider)
        withStateLock {
            generation = loadGeneration
            self.fetcher = fetcher
        }
        fetcher.start { [weak self] data in
            guard let data else { return }
            DispatchQueue.main.async {
                guard let self, self.isCurrent(loadGeneration),
                      let image = Self.decode(data) else { return }
                self.image = image
                self.withStateLock {
                    if self.generation == loadGeneration { self.fetcher = nil }
                }
            }
        }
    }

    func cancel() {
        let fetcher = withStateLock { () -> VideoDownloaderImageFetcher? in
            generation = UUID()
            let active = self.fetcher
            self.fetcher = nil
            return active
        }
        fetcher?.cancel()
        image = nil
    }

    private func isCurrent(_ value: UUID) -> Bool {
        withStateLock { generation == value }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private static func decode(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= VideoDownloaderThumbnailURLPolicy.maximumPixelDimension,
              height <= VideoDownloaderThumbnailURLPolicy.maximumPixelDimension else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: thumbnail,
                       size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}

#if !VORSSAINT_TEST

private struct VideoDownloaderThumbnailView: View {
    @StateObject private var loader: VideoDownloaderThumbnailLoader
    let compact: Bool

    init(url: URL, compact: Bool) {
        _loader = StateObject(wrappedValue: VideoDownloaderThumbnailLoader(url: url))
        self.compact = compact
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06))
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: compact ? 94 : 132, height: compact ? 58 : 78)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onAppear { loader.load() }
        .onDisappear { loader.cancel() }
    }
}

private enum VideoDownloaderDestinationPicker {
    private static var modalActive = false

    /// Menu bar items run without app key status. Activate the application first and defer
    /// NSOpenPanel to the next run loop turn so macOS properly routes keyboard and mouse events.
    static func present(current: URL, completion: @escaping (URL) -> Void) {
        guard !modalActive else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current

        modalActive = true
        let restorePopover = appDelegate()?.suspendPopoverForModalPanel() ?? false
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let response = panel.runModal()
            modalActive = false
            QuickLauncherService.shared.refocusAfterModal()
            defer {
                appDelegate()?.restorePopoverAfterModalPanelIfNeeded(wasShown: restorePopover)
            }
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    static func present(for workflow: VideoDownloaderWorkflow) {
        present(current: workflow.destination) { url in
            workflow.setDestination(url)
        }
    }
}

struct PanelVideoDownloaderView: View {
    let close: () -> Void

    var body: some View {
        VideoDownloaderWorkspaceView(compact: true, onClose: close)
            .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
            .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
    }
}

struct VideoDownloaderWorkspaceView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var workflow = VideoDownloaderWorkflow.shared
    @FocusState private var sourceFieldFocused: Bool
    let compact: Bool
    var onClose: (() -> Void)? = nil

    private var text: VideoDownloaderStrings { FeatureStrings.videoDownloader(l10n.language) }
    private var controlsLocked: Bool { workflow.phase.locksRequest }
    private var subtitleSelection: Binding<String> {
        Binding(
            get: { workflow.subtitle?.id ?? "" },
            set: workflow.selectSubtitle(id:)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            header
            sourceCard
            if let notice = workflow.inspectionNotice, workflow.phase == .ready {
                inspectionNoticeView(notice)
            }
            if workflow.isInitialDependencyProbe || !workflow.missingTools.isEmpty
                || workflow.phase == .settingUp || workflow.isCancellingSetup {
                VideoDownloaderDependencyCard(alwaysShow: false)
            }
            if let media = workflow.media {
                mediaDetails(media)
                requestControls(media)
            }
            destinationRow
            stateControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            workflow.prepareForUse()
            guard workflow.sourceText.isEmpty, !controlsLocked else { return }
            DispatchQueue.main.async { sourceFieldFocused = true }
        }
        .animation(.easeInOut(duration: 0.18), value: workflow.phase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(text.pageTitle, systemImage: "arrow.down.circle")
                    .font(compact ? .headline : .title2.weight(.semibold))
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.menuClose)
                    .accessibilityLabel(l10n.s.menuClose)
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .foregroundStyle(Color.accentColor)
                sectionTitle("URL")
                Spacer(minLength: 0)
                if workflow.phase == .inspecting {
                    ProgressView()
                        .controlSize(.small)
                    Text(text.inspecting)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 7) {
                ZStack(alignment: .trailing) {
                    TextField(text.urlPlaceholder,
                              text: Binding(get: { workflow.sourceText },
                                            set: workflow.setSourceText))
                        .textFieldStyle(.roundedBorder)
                        .padding(.trailing, workflow.sourceText.isEmpty ? 0 : 20)
                        .disabled(controlsLocked)
                        .focused($sourceFieldFocused)
                        .help(text.urlHelp)
                        .accessibilityLabel(text.urlPlaceholder)

                    if !workflow.sourceText.isEmpty && !controlsLocked {
                        Button {
                            workflow.setSourceText("")
                            sourceFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.s.urlCleanerClearButton)
                        .accessibilityLabel(l10n.s.urlCleanerClearButton)
                        .padding(.trailing, 0)
                        .offset(x: 4)
                    }
                }
                Button(text.paste) { workflow.pasteURL() }
                    .disabled(controlsLocked)
            }

            if !compact {
                Text(text.urlHelp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let validationError = workflow.validationError {
                message(text.message(for: validationError), color: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private func inspectionNoticeView(_ notice: VideoDownloaderFailure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(text.message(for: notice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if shouldShowRateLimitHelp(for: notice) {
                    rateLimitHelpView
                }
                Text(text.inspectionFailedNotice)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(text.retry) { workflow.retry() }
                .controlSize(.small)
                .accessibilityLabel(text.retry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private func mediaDetails(_ media: VideoDownloaderMedia) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let thumbnailURL = media.thumbnailURL {
                VideoDownloaderThumbnailView(url: thumbnailURL, compact: compact)
                    .id(thumbnailURL)
                    .accessibilityLabel(text.thumbnail)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
                .frame(width: compact ? 94 : 132, height: compact ? 58 : 78)
                .accessibilityLabel(text.thumbnail)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .lineLimit(2)
                if let uploader = media.uploader, !uploader.isEmpty {
                    Label(uploader, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(text.uploader): \(uploader)")
                }
                let sizeText = currentEstimatedSizeText(for: media)
                if media.duration != nil || sizeText != nil {
                    HStack(spacing: 6) {
                        if let duration = media.duration {
                            Label(durationText(duration), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("\(text.duration): \(durationText(duration))")
                        }
                        if let sizeText {
                            if media.duration != nil {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Label(sizeText, systemImage: "internaldrive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(sizeText)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private func requestControls(_ media: VideoDownloaderMedia) -> some View {
        let modeLabel = "\(text.video) / \(text.audio)"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.accentColor)
                sectionTitle(text.outputOptions)
                Spacer(minLength: 0)
            }

            Picker(modeLabel,
                   selection: Binding(get: {
                       workflow.mode
                   }, set: { value in
                       workflow.setMode(value)
                   })) {
                Text(text.video).tag(VideoDownloaderOutputMode.video)
                Text(text.audio).tag(VideoDownloaderOutputMode.audio)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(modeLabel)
            .disabled(controlsLocked)

            if workflow.mode == .video {
                HStack(spacing: 8) {
                    Text(text.quality)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if media.heights.isEmpty {
                        Text("—")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(text.quality)
                    } else {
                        Picker(text.quality, selection: Binding(
                            get: { workflow.quality },
                            set: workflow.setQuality
                        )) {
                            ForEach(media.heights, id: \.self) { height in
                                Text(String(format: text.heightFormat, height))
                                    .tag(VideoDownloaderQuality.height(height))
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(text.quality)
                        .disabled(controlsLocked || !media.canAttemptVideo)
                    }
                }

                let subtitleOptions = media.subtitleOptions
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: {
                        workflow.subtitlesEnabled
                    }, set: workflow.setSubtitlesEnabled)) {
                        Label(text.subtitles, systemImage: "captions.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .disabled(controlsLocked || subtitleOptions.isEmpty)
                    Spacer(minLength: 0)

                    if subtitleOptions.isEmpty {
                        Text(text.none)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Picker(text.subtitles, selection: subtitleSelection) {
                            ForEach(subtitleOptions) { track in
                                Text(subtitleLabel(track)).tag(track.id)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(text.subtitles)
                        .disabled(controlsLocked || !workflow.subtitlesEnabled)
                        .opacity(workflow.subtitlesEnabled ? 1 : 0.55)
                    }
                }
            }

            if media.videoAvailability == .unavailable {
                message(text.errorNoVideo, color: .orange)
            }
            if media.audioAvailability == .unavailable {
                message(text.errorNoAudio, color: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .foregroundStyle(Color.accentColor)
                sectionTitle(text.destination)
                Spacer(minLength: 0)
                Button(text.choose, action: chooseDestination)
                    .controlSize(.small)
                    .disabled(controlsLocked)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(workflow.destination.lastPathComponent)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(displayPath(for: workflow.destination))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(workflow.destination)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(text.revealFinder)
                .accessibilityLabel(text.revealFinder)
            }
        }
        .help(workflow.destination.path)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    @ViewBuilder
    private var stateControls: some View {
        switch workflow.phase {
        case .cancelling where workflow.isCancellingSetup:
            EmptyView()
        case .downloading, .finalizing, .cancelling:
            activeDownload
        case .completed:
            completionView
        case .failed:
            failureView
        case .cancelled:
            VStack(alignment: .leading, spacing: 7) {
                message(text.cancelled, color: .secondary)
                Button(text.retry) { workflow.retry() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard()
        case .inspecting, .settingUp:
            EmptyView()
        case .idle, .ready:
            if workflow.isInitialDependencyProbe || !workflow.missingTools.isEmpty {
                EmptyView()
            } else {
                primaryAction
            }
        }
    }

    private var primaryAction: some View {
        Button {
            workflow.startDownload()
        } label: {
            Label(workflow.mode == .video ? text.downloadVideo : text.downloadAudio,
                  systemImage: "arrow.down.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(compact ? .regular : .large)
        .disabled(!workflow.canDownload)
    }

    private var activeDownload: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(text.downloading, systemImage: "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(workflow.activeTitle ?? workflow.media?.title ?? text.downloading)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(2)
            qualityFallbackNotice
            if let fraction = workflow.progress.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            HStack(spacing: 8) {
                Text(activeStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if workflow.phase != .cancelling {
                    Button(text.cancel) { workflow.cancelActiveOperation() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private var activeStatus: String {
        if workflow.phase == .cancelling { return text.cancelling }
        if workflow.phase == .finalizing { return text.finalizing }
        var parts: [String] = []
        if let fraction = workflow.progress.fraction {
            parts.append(String(format: text.percentFormat, fraction * 100))
        }
        if let speed = workflow.progress.speedBytesPerSecond {
            parts.append(String(format: text.speedFormat, speedText(speed)))
        }
        if let eta = workflow.progress.etaSeconds {
            parts.append(String(format: text.etaFormat, durationText(eta)))
        }
        return parts.isEmpty ? text.downloading : parts.joined(separator: " · ")
    }

    private var completionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text.complete, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12, weight: .semibold))
            if let file = workflow.completedFile {
                Text(file.lastPathComponent)
                    .font(.caption)
                    .lineLimit(2)
                    .help(file.path)
            }
            qualityFallbackNotice
            ForEach(workflow.warnings, id: \.self) { warning in
                Label(text.message(for: warning), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(text.downloadAnother) { workflow.downloadAnother() }
                Spacer(minLength: 0)
                Button(text.revealFinder) { workflow.revealCompletedFile() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    @ViewBuilder
    private var qualityFallbackNotice: some View {
        if let fallback = workflow.qualityFallback {
            Label(String(format: text.qualityFallbackFormat,
                         fallback.requestedHeight,
                         fallback.actualHeight),
                  systemImage: "arrow.down.right.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var failureView: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(text.failureTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            if let failure = workflow.failure {
                Text(text.message(for: failure))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if shouldShowRateLimitHelp(for: failure) {
                    rateLimitHelpView
                }
                if failure == .cookiesPermission {
                    FullDiskAccessNote(compact: true, note: text.cookiesDiskAccessNote)
                }
            }
            Button(text.retry) { workflow.retry() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private var rateLimitHelpView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text.cookiesCaptchaNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Link(text.faq,
                 destination: URL(string: "https://github.com/yt-dlp/yt-dlp/wiki/FAQ")!)
                .font(.caption2)
        }
    }

    private func shouldShowRateLimitHelp(for failure: VideoDownloaderFailure) -> Bool {
        switch failure {
        case .rateLimited:
            return true
        case let .extractorError(message):
            return VideoDownloaderRateLimitSupport.shouldSuggestRateLimitHelp(message)
        default:
            return false
        }
    }

    private func message(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func subtitleLabel(_ track: VideoDownloaderSubtitleTrack) -> String {
        let language = VideoDownloaderSubtitleSelection.localizedName(for: track,
                                                                       appLanguage: l10n.language)
        return language + " · " + (track.source == .manual ? text.manual : text.automatic)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let value = VideoDownloaderNumericPolicy.wholeSeconds(seconds) ?? 0
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    private func currentEstimatedSizeText(for media: VideoDownloaderMedia) -> String? {
        let bytes: Int64?
        switch workflow.mode {
        case .video:
            let targetHeight: Int?
            switch workflow.quality {
            case let .height(h): targetHeight = h
            case .best: targetHeight = media.heights.first
            }
            bytes = targetHeight.flatMap { media.estimatedSizes[$0] }
        case .audio:
            bytes = media.estimatedAudioSize
        }
        return VideoDownloaderByteCountFormatter.formattedApproximateSize(bytes)
    }

    private func speedText(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = max(0, bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 { value /= 1000; index += 1 }
        return value >= 10 || index == 0
            ? String(format: "%.0f %@", value, units[index])
            : String(format: "%.1f %@", value, units[index])
    }

    private func displayPath(for url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + String(path.dropFirst(home.count + 1))
        }
        return path
    }

    private func chooseDestination() {
        VideoDownloaderDestinationPicker.present(for: workflow)
    }
}

struct VideoDownloaderDependencyCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var workflow = VideoDownloaderWorkflow.shared
    @State private var detailsExpanded = false
    let alwaysShow: Bool

    private var text: VideoDownloaderStrings { FeatureStrings.videoDownloader(l10n.language) }

    private struct DependencyGroup: Identifiable {
        let id: String
        let title: String
        let tools: [VideoDownloaderTool]
    }

    private let dependencyGroups = [
        DependencyGroup(id: "yt-dlp", title: "yt-dlp", tools: [.ytDlp]),
        DependencyGroup(id: "ffmpeg", title: "FFmpeg", tools: [.ffmpeg, .ffprobe]),
        DependencyGroup(id: "deno", title: "Deno", tools: [.deno]),
    ]

    private var shouldShowCard: Bool {
        alwaysShow || workflow.isInitialDependencyProbe
            || !workflow.missingTools.isEmpty || workflow.phase == .settingUp
            || workflow.terminalSetupPending
    }

    private var detailsForcedOpen: Bool {
        workflow.isInitialDependencyProbe || !workflow.missingTools.isEmpty
            || workflow.phase == .settingUp || workflow.isCancellingSetup
            || workflow.terminalSetupPending
    }

    private var detailsBinding: Binding<Bool> {
        Binding(
            get: { detailsExpanded || detailsForcedOpen },
            set: { detailsExpanded = $0 }
        )
    }

    private var missingToolNames: String {
        dependencyGroups
            .filter { group in group.tools.contains { workflow.missingTools.contains($0) } }
            .map(\.title)
            .joined(separator: ", ")
    }

    var body: some View {
        if shouldShowCard {
            if alwaysShow {
                DisclosureGroup(isExpanded: detailsBinding) {
                    dependencyDetails
                } label: {
                    dependencySummary
                }
                .panelCard()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    dependencyHeader
                    dependencyDetails
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelCard()
            }
        }
    }

    private var dependencySummary: some View {
        HStack(spacing: 7) {
            Label(text.dependencies, systemImage: "shippingbox")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            if workflow.dependencyState.value == nil {
                Text(text.checkingTools)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let ready = workflow.missingTools.isEmpty
                Label(ready ? l10n.s.homebrewInstalledBadge : l10n.s.homebrewNotInstalledBadge,
                      systemImage: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ready ? .green : .orange)
            }
        }
    }

    private var dependencyHeader: some View {
        HStack(spacing: 7) {
            Label(text.dependencies, systemImage: "shippingbox")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            if workflow.isProbingDependencies && workflow.phase != .settingUp {
                ProgressView()
                    .controlSize(.small)
                Text(text.checkingTools)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var dependencyDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(dependencyGroups) { group in
                HStack {
                    Text(group.title)
                        .font(.system(size: 11, design: .monospaced))
                    Spacer()
                    if workflow.dependencyState.value == nil {
                        ProgressView().controlSize(.small)
                    } else {
                        let available = group.tools.allSatisfy { !workflow.missingTools.contains($0) }
                        Label(available ? l10n.s.homebrewInstalledBadge : l10n.s.homebrewNotInstalledBadge,
                              systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(available ? .green : .orange)
                    }
                }
            }
            if !workflow.missingTools.isEmpty {
                Text(String(format: text.missingToolsFormat, missingToolNames))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(VideoDownloaderDependencySupport.brewPath() == nil
                     || workflow.terminalSetupPending
                     ? text.terminalSetupNote : text.brewSetupNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if workflow.phase == .settingUp || workflow.isCancellingSetup {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(workflow.isCancellingSetup ? text.cancelling : text.checkingTools)
                        .font(.caption)
                    Spacer()
                    if workflow.phase == .settingUp && workflow.canCancelSetup {
                        Button(text.cancel) { workflow.cancelActiveOperation() }
                    }
                }
            } else if workflow.terminalSetupPending {
                Button(text.checkDependencies) { workflow.checkDependencies() }
                    .buttonStyle(.borderedProminent)
            } else if !workflow.missingTools.isEmpty {
                Button(VideoDownloaderDependencySupport.brewPath() == nil
                       ? text.setUpDownloader : text.installMissingTools) {
                    workflow.setupDependencies()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!workflow.canSetupDependencies)
            }
        }
    }
}

struct VideoDownloaderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var workflow = VideoDownloaderWorkflow.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.panelUtilityVideoDownloader) private var showInPanel = true
    @AppStorage(DefaultsKey.videoDownloaderEmbedThumbnail) private var thumbnail = true
    @AppStorage(DefaultsKey.videoDownloaderEmbedMetadata) private var metadata = true
    @AppStorage(DefaultsKey.videoDownloaderEmbedChapters) private var chapters = true
    @AppStorage(DefaultsKey.videoDownloaderUseBrowserCookies) private var useBrowserCookies = false
    @AppStorage(DefaultsKey.videoDownloaderCookiesBrowser) private var cookiesBrowser = "safari"
    @State private var showCookieDetails = false

    private var text: VideoDownloaderStrings { FeatureStrings.videoDownloader(l10n.language) }

    var body: some View {
        Form {
            Section {
                Text(text.settingsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(text.showInPanel, isOn: $showInPanel)
            }
            Section(text.defaultLocation) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workflow.destination.lastPathComponent)
                        Text(workflow.destination.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(text.choose, action: chooseDestination)
                    Button(text.resetDownloads) { workflow.resetDestination() }
                }
            }
            Section {
                Toggle(text.embedThumbnail, isOn: $thumbnail)
                Toggle(text.embedMetadata, isOn: $metadata)
                Toggle(text.embedChapters, isOn: $chapters)
            }
            Section {
                Toggle(text.useCookies, isOn: $useBrowserCookies)
                if useBrowserCookies {
                    Picker(text.cookiesBrowser, selection: $cookiesBrowser) {
                        ForEach(VideoDownloaderCookiesSupport.supportedBrowsers, id: \.self) { browser in
                            Text(browser.capitalized).tag(browser)
                        }
                    }
                    Text(text.cookiesNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(isExpanded: $showCookieDetails) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text.cookiesCaptchaNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Link(text.faq,
                                 destination: URL(string: "https://github.com/yt-dlp/yt-dlp/wiki/FAQ")!)
                                .font(.caption)
                            if !permissions.fullDiskAccess {
                                FullDiskAccessNote(note: text.cookiesDiskAccessNote)
                            } else {
                                Label(text.cookiesDiskAccessNote,
                                      systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } label: {
                        Text(showCookieDetails
                             ? l10n.s.homebrewOperationHideDetails
                             : l10n.s.homebrewOperationShowDetails)
                            .font(.caption)
                    }
                }
            }
            Section {
                VideoDownloaderDependencyCard(alwaysShow: true)
            }
            Section {
                Text(text.usageNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(text.pageTitle)
        .onAppear { workflow.prepareForUse() }
        .padding()
    }

    private func chooseDestination() {
        VideoDownloaderDestinationPicker.present(for: workflow)
    }
}
#endif
