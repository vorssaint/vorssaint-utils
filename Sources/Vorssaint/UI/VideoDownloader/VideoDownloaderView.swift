// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import Combine
import Foundation
import ImageIO
#if !VORSSAINT_TEST
import SwiftUI
#endif

final class VideoDownloaderThumbnailImageCache {
    static let shared = VideoDownloaderThumbnailImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    init(countLimit: Int = 24, totalCostLimit: Int = 32 * 1024 * 1024) {
        cache.countLimit = max(1, countLimit)
        cache.totalCostLimit = max(1, totalCostLimit)
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        let pixelCost = max(1, Int(image.size.width * image.size.height * 4))
        cache.setObject(image, forKey: url as NSURL, cost: pixelCost)
    }
}

final class VideoDownloaderThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private let url: URL
    private let endpointValidator: (URL) -> Bool
    private let configurationProvider: () -> URLSessionConfiguration
    private let imageCache: VideoDownloaderThumbnailImageCache
    private let stateLock = NSLock()
    private var fetcher: VideoDownloaderImageFetcher?
    private var generation = UUID()

    init(url: URL,
         endpointValidator: @escaping (URL) -> Bool = {
             VideoDownloaderThumbnailURLPolicy.resolvesToPublicEndpoint($0)
         },
         configurationProvider: @escaping () -> URLSessionConfiguration = {
             URLSessionConfiguration.ephemeral
         },
         imageCache: VideoDownloaderThumbnailImageCache = .shared) {
        self.url = url
        self.endpointValidator = endpointValidator
        self.configurationProvider = configurationProvider
        self.imageCache = imageCache
        image = imageCache.image(for: url)
    }

    func load() {
        if let cached = imageCache.image(for: url) {
            image = cached
            return
        }
        guard withStateLock({ self.fetcher == nil }) else { return }
        let loadGeneration = UUID()
        let fetcher = VideoDownloaderImageFetcher(url: url,
                                                   timeout: 8,
                                                   endpointValidator: endpointValidator,
                                                   configurationProvider: configurationProvider)
        withStateLock {
            generation = loadGeneration
            self.fetcher = fetcher
        }
        fetcher.start { [weak self, imageCache, url] data in
            guard let data else {
                self?.clearFetcher(for: loadGeneration)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = Self.decode(data) else {
                    self?.clearFetcher(for: loadGeneration)
                    return
                }
                imageCache.insert(image, for: url)
                DispatchQueue.main.async {
                    guard let self, self.isCurrent(loadGeneration) else { return }
                    self.image = image
                    self.clearFetcher(for: loadGeneration)
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
    }

    private func isCurrent(_ value: UUID) -> Bool {
        withStateLock { generation == value }
    }

    private func clearFetcher(for loadGeneration: UUID) {
        withStateLock {
            if generation == loadGeneration { fetcher = nil }
        }
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

struct VideoDownloaderQualityLayout: Equatable {
    static let primaryLimit = 3

    let primaryHeights: [Int]
    let additionalHeights: [Int]

    init(heights: [Int]) {
        let normalized = Array(Set(heights.filter { $0 > 0 })).sorted(by: >)
        primaryHeights = Array(normalized.prefix(Self.primaryLimit))
        additionalHeights = Array(normalized.dropFirst(Self.primaryLimit))
    }

    var hasAdditionalHeights: Bool { !additionalHeights.isEmpty }

    func visibleHeights(isExpanded: Bool, selectedHeight: Int? = nil) -> [Int] {
        guard !isExpanded,
              let selectedHeight,
              additionalHeights.contains(selectedHeight) else {
            return isExpanded ? primaryHeights + additionalHeights : primaryHeights
        }
        return primaryHeights + [selectedHeight]
    }

    func additionalHeightsForExpansion(selectedHeight: Int?) -> [Int] {
        additionalHeights.filter { $0 != selectedHeight }
    }
}

struct VideoDownloaderSubtitleControlLayout: Equatable {
    let showsControl: Bool
    let showsLanguagePicker: Bool

    init(hasSubtitleOptions: Bool, subtitlesEnabled: Bool) {
        showsControl = hasSubtitleOptions
        showsLanguagePicker = hasSubtitleOptions && subtitlesEnabled
    }
}

enum VideoDownloaderInspectionPresentation: Hashable {
    case hidden
    case loading
    case content

    static func resolve(phase: VideoDownloaderPhase,
                        hasMedia: Bool,
                        isInspectionPending: Bool) -> VideoDownloaderInspectionPresentation {
        if phase == .inspecting || isInspectionPending { return .loading }
        return [.ready, .failed].contains(phase) && hasMedia ? .content : .hidden
    }
}

enum VideoDownloaderSourceFieldLayout {
    static func trailingInset(hasSourceText: Bool) -> CGFloat {
        hasSourceText ? 20 : 0
    }
}

enum VideoDownloaderIdleActionLayout {
    static func shouldShowPrimaryAction(phase: VideoDownloaderPhase,
                                        hasMedia: Bool,
                                        isInitialDependencyProbe: Bool,
                                        hasMissingTools: Bool) -> Bool {
        phase == .ready
            && hasMedia
            && !isInitialDependencyProbe
            && !hasMissingTools
    }
}

#if !VORSSAINT_TEST

// MARK: - Shimmer Skeleton Loading (Plan B)

private struct VideoDownloaderShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.16),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(geo.size.width * 1.5, 100))
                    .offset(x: phase * max(geo.size.width * 1.5, 100))
                    .opacity(reduceMotion ? 0 : 1)
                }
            )
            .mask(content)
            .onAppear {
                guard !reduceMotion else {
                    phase = 0
                    return
                }
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
}

private struct VideoDownloaderSkeletonCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PanelSurface.controlFill(for: colorScheme))
                .frame(width: compact ? 96 : 136, height: compact ? 54 : 76)
                .modifier(VideoDownloaderShimmerModifier())

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PanelSurface.controlFill(for: colorScheme))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                    .modifier(VideoDownloaderShimmerModifier())

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PanelSurface.controlFill(for: colorScheme))
                    .frame(width: 110, height: 10)
                    .modifier(VideoDownloaderShimmerModifier())

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PanelSurface.controlFill(for: colorScheme))
                    .frame(width: 75, height: 9)
                    .modifier(VideoDownloaderShimmerModifier())
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(PanelSurface.controlFill(for: colorScheme).opacity(0.35))
        )
    }
}

private struct VideoDownloaderResultHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Thumbnail & Media Showcase (Plan A)

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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: "photo")
                        .font(.system(size: compact ? 15 : 20))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: compact ? 96 : 136, height: compact ? 54 : 76)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { loader.load() }
        .onDisappear { loader.cancel() }
    }
}

private struct VideoDownloaderThumbnailShowcaseView: View {
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let compact: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbnailURL {
                VideoDownloaderThumbnailView(url: thumbnailURL, compact: compact)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: "photo")
                        .font(.system(size: compact ? 15 : 20))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: compact ? 96 : 136, height: compact ? 54 : 76)
            }

            if let duration {
                Text(formatDuration(duration))
                    .font(.system(size: compact ? 8 : 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.black.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    .padding(3.5)
            }
        }
        .frame(width: compact ? 96 : 136, height: compact ? 54 : 76)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = VideoDownloaderNumericPolicy.wholeSeconds(seconds) ?? 0
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}

// MARK: - Quality Chip Button (Plan B)

private struct QualityChipButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5.5)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : PanelSurface.controlFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : PanelSurface.border(for: colorScheme), lineWidth: isSelected ? 1.3 : 0.7)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .opacity(isEnabled ? 1.0 : 0.45)
    }
}

// MARK: - Destination Picker Modal Helper

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

// MARK: - Main Panel Container

struct PanelVideoDownloaderView: View {
    let close: () -> Void

    var body: some View {
        VideoDownloaderWorkspaceView(compact: true, onClose: close)
            .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
            .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
    }
}

// MARK: - Workspace Redesign Orchestrator

struct VideoDownloaderWorkspaceView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var workflow = VideoDownloaderWorkflow.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var sourceFieldFocused: Bool
    @State private var qualityOptionsExpanded = false
    @State private var errorDetailsCopied = false
    @State private var rateLimitHelpExpanded = false
    @State private var retainedInspectionResultHeight: CGFloat = 0
    let compact: Bool
    var onClose: (() -> Void)? = nil

    private var text: VideoDownloaderStrings { FeatureStrings.videoDownloader(l10n.language) }
    private var controlsLocked: Bool { workflow.phase.locksRequest }
    private var hasClearSourceText: Bool { !workflow.sourceText.isEmpty && !controlsLocked }
    private var inspectionPresentation: VideoDownloaderInspectionPresentation {
        VideoDownloaderInspectionPresentation.resolve(phase: workflow.phase,
                                                       hasMedia: workflow.media != nil,
                                                       isInspectionPending: workflow.isInspectionPending)
    }
    private var resultContentTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.animation(.easeInOut(duration: 0.15))
    }
    private var retainedLoadingHeight: CGFloat? {
        inspectionPresentation == .loading && retainedInspectionResultHeight > 0
            ? retainedInspectionResultHeight : nil
    }
    private var shouldShowPrimaryAction: Bool {
        VideoDownloaderIdleActionLayout.shouldShowPrimaryAction(
            phase: workflow.phase,
            hasMedia: workflow.media != nil,
            isInitialDependencyProbe: workflow.isInitialDependencyProbe,
            hasMissingTools: !workflow.missingTools.isEmpty
        )
    }
    private var subtitleSelection: Binding<String> {
        Binding(
            get: { workflow.subtitle?.id ?? "" },
            set: workflow.selectSubtitle(id:)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            header
            flowSurface
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            workflow.prepareForUse()
            guard workflow.sourceText.isEmpty, !controlsLocked else { return }
            DispatchQueue.main.async { sourceFieldFocused = true }
        }
        .onChange(of: workflow.phase) { _, phase in
            announceStatus(for: phase)
        }
        .onChange(of: workflow.validationError) { _, failure in
            guard let failure else { return }
            postAccessibilityAnnouncement(text.message(for: failure), priority: .high)
        }
        .onChange(of: workflow.inspectionNotice) { _, failure in
            guard let failure else { return }
            postAccessibilityAnnouncement(text.message(for: failure), priority: .high)
        }
        .onChange(of: workflow.media?.heights) { _, _ in
            qualityOptionsExpanded = false
        }
        .onChange(of: workflow.failure) { _, _ in
            errorDetailsCopied = false
            rateLimitHelpExpanded = false
        }
        .onChange(of: inspectionPresentation) { _, presentation in
            if presentation == .hidden {
                retainedInspectionResultHeight = 0
            }
        }
        .onExitCommand(perform: handleExitCommand)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22),
                   value: usesFocusedStateLayout)
    }

    private var flowSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            if usesFocusedStateLayout {
                if let media = workflow.media {
                    mediaSummary(media)
                    flowDivider
                }
                stateControls
            } else {
                sourceSection

                inspectionResultSection

                if workflow.isInitialDependencyProbe || !workflow.missingTools.isEmpty
                    || workflow.phase == .settingUp || workflow.isCancellingSetup {
                    flowDivider
                    VideoDownloaderDependencyCard(alwaysShow: false)
                }

                if shouldShowStateControls {
                    flowDivider
                    stateControls
                }
            }
        }
        .padding(compact ? 11 : 16)
        .background(
            RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous)
                .fill(PanelSurface.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        )
    }

    @ViewBuilder
    private var inspectionResultSection: some View {
        if inspectionPresentation != .hidden {
            inspectionResultContent
                .frame(maxWidth: .infinity, minHeight: retainedLoadingHeight, alignment: .topLeading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: VideoDownloaderResultHeightPreferenceKey.self,
                            value: inspectionPresentation == .content ? proxy.size.height : 0)
                    }
                )
                .onPreferenceChange(VideoDownloaderResultHeightPreferenceKey.self) { height in
                    guard inspectionPresentation == .content, height > 0 else { return }
                    retainedInspectionResultHeight = height
                }
                .id(inspectionPresentation)
                .transition(resultContentTransition)
        }
    }

    @ViewBuilder
    private var inspectionResultContent: some View {
        switch inspectionPresentation {
        case .hidden:
            EmptyView()
        case .loading:
            flowDivider
            VideoDownloaderSkeletonCard(compact: compact)
        case .content:
            if let notice = workflow.inspectionNotice {
                flowDivider
                inspectionNoticeView(notice)
            }
            if let media = workflow.media {
                flowDivider
                mediaSummary(media)
                flowDivider
                outputOptionsSection(media)
            }
        }
    }

    private var flowDivider: some View {
        Divider()
            .padding(.vertical, compact ? 9 : 13)
    }

    private var shouldShowStateControls: Bool {
        switch workflow.phase {
        case .cancelling where workflow.isCancellingSetup, .inspecting, .settingUp:
            return false
        case .idle, .ready:
            return shouldShowPrimaryAction
        default:
            return true
        }
    }

    private var usesFocusedStateLayout: Bool {
        switch workflow.phase {
        case .downloading, .finalizing, .cancelling, .completed:
            return !workflow.isCancellingSetup
        default:
            return false
        }
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
            if !compact {
                Text(text.hubDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Input Bar

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
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
                        .padding(.trailing, VideoDownloaderSourceFieldLayout.trailingInset(
                            hasSourceText: !workflow.sourceText.isEmpty))
                        .disabled(controlsLocked)
                        .focused($sourceFieldFocused)
                        .help(text.urlHelp)
                        .accessibilityLabel(text.urlPlaceholder)

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
                    .accessibilityHidden(!hasClearSourceText)
                    .allowsHitTesting(hasClearSourceText)
                    .opacity(hasClearSourceText ? 1 : 0)
                    .padding(.trailing, 0)
                    .offset(x: 4)
                }

                Button {
                    workflow.pasteURL()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11))
                        Text(text.paste)
                    }
                }
                .disabled(controlsLocked)
            }

            if !compact {
                Text(text.urlHelp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(workflow.sourceText.isEmpty ? 1 : 0)
                    .accessibilityHidden(!workflow.sourceText.isEmpty)
            }

            if let validationError = workflow.validationError {
                message(text.message(for: validationError), color: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.vertical, 1)
    }

    // MARK: - Media Showcase Card (Plan A)

    private func mediaSummary(_ media: VideoDownloaderMedia) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VideoDownloaderThumbnailShowcaseView(
                thumbnailURL: media.previewThumbnailURL,
                duration: media.duration,
                compact: compact
            )
            .accessibilityLabel(thumbnailAccessibilityLabel(for: media))

            VStack(alignment: .leading, spacing: 5) {
                Text(media.title)
                    .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                    .lineLimit(2)

                if let uploader = media.uploader, !uploader.isEmpty {
                    Label(uploader, systemImage: "person.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("\(text.uploader): \(uploader)")
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Quality & Format Selection (Plan B)

    private func outputOptionsSection(_ media: VideoDownloaderMedia) -> some View {
        let modeLabel = "\(text.video) / \(text.audio)"
        let subtitleLayout = VideoDownloaderSubtitleControlLayout(
            hasSubtitleOptions: !media.subtitleOptions.isEmpty,
            subtitlesEnabled: workflow.subtitlesEnabled)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
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
                qualitySelectionSection(media)

                if subtitleLayout.showsControl {
                    subtitleOptionsSection(media, layout: subtitleLayout)
                }
            } else {
                if let audioSize = media.estimatedAudioSize {
                    HStack(spacing: 6) {
                        Image(systemName: "headphones")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(text.audio)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(VideoDownloaderByteCountFormatter.formattedApproximateSize(audioSize) ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(PanelSurface.controlFill(for: colorScheme))
                    )
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
    }

    private func qualitySelectionSection(_ media: VideoDownloaderMedia) -> some View {
        let layout = VideoDownloaderQualityLayout(heights: media.heights)
        let disclosureTitle = qualityOptionsExpanded ? text.fewerQualities : text.moreQualities
        let selectedHeight: Int? = {
            if case let .height(value) = workflow.quality { return value }
            return nil
        }()
        let visibleHeights = layout.visibleHeights(isExpanded: qualityOptionsExpanded, selectedHeight: selectedHeight)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(text.quality)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)

                if layout.hasAdditionalHeights {
                    Button {
                        qualityOptionsExpanded.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(disclosureTitle)
                            Image(systemName: qualityOptionsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controlsLocked)
                    .accessibilityLabel("\(text.quality), \(disclosureTitle)")
                }
            }

            if layout.primaryHeights.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityLabel(text.quality)
            } else {
                qualityChipGrid(media, heights: visibleHeights)
            }
        }
    }

    private func qualityChipGrid(_ media: VideoDownloaderMedia, heights: [Int]) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: compact ? 74 : 92), spacing: 6),
            count: VideoDownloaderQualityLayout.primaryLimit)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(heights, id: \.self) { height in
                let isSelected: Bool = {
                    switch workflow.quality {
                    case let .height(h): return h == height
                    case .best: return height == media.heights.first
                    }
                }()
                let sizeText = media.estimatedSizes[height].flatMap {
                    VideoDownloaderByteCountFormatter.formattedApproximateSize($0)
                }

                QualityChipButton(
                    title: qualityChipTitle(for: height),
                    subtitle: sizeText,
                    isSelected: isSelected,
                    isEnabled: !controlsLocked && media.canAttemptVideo
                ) {
                    workflow.setQuality(.height(height))
                }
                .accessibilityLabel(String(format: text.heightFormat, height))
                .accessibilityValue(sizeText ?? "")
            }
        }
    }

    private func subtitleOptionsSection(_ media: VideoDownloaderMedia,
                                        layout: VideoDownloaderSubtitleControlLayout) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(get: {
                workflow.subtitlesEnabled
            }, set: workflow.setSubtitlesEnabled)) {
                Label(text.subtitles, systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .disabled(controlsLocked || media.subtitleOptions.isEmpty)

            if layout.showsLanguagePicker {
                Picker(l10n.s.languageLabel, selection: subtitleSelection) {
                    ForEach(media.subtitleOptions) { track in
                        Text(subtitleLabel(track)).tag(track.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(controlsLocked)
            }
        }
        .padding(.top, 3)
    }

    // MARK: - State Controls Router

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
        case .inspecting, .settingUp:
            EmptyView()
        case .idle, .ready:
            if shouldShowPrimaryAction {
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
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Active Download

    private var activeDownload: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 13))
                Text(activeStageTitle.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(activeStageTitle)
                Spacer(minLength: 0)
                if let fraction = workflow.progress.fraction {
                    Text(String(format: "%.0f%%", fraction * 100))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(workflow.activeTitle ?? workflow.media?.title ?? text.downloading)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)

            qualityFallbackNotice

            // Progress Bar
            if let fraction = workflow.progress.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .accessibilityLabel(activeStageTitle)
                    .accessibilityValue(String(format: text.percentFormat, fraction * 100))
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel(activeStageTitle)
            }

            HStack(spacing: 8) {
                Text(activeMetricSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if workflow.phase != .cancelling {
                    Button(text.cancel) { workflow.cancelActiveOperation() }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeStageTitle: String {
        switch workflow.phase {
        case .finalizing: return text.finalizing
        case .cancelling: return text.cancelling
        default: return text.downloading
        }
    }

    private var activeMetricSummary: String {
        guard workflow.phase == .downloading else { return activeStageTitle }
        var parts: [String] = []
        if let speed = workflow.progress.speedBytesPerSecond {
            parts.append(String(format: text.speedFormat, speedText(speed)))
        }
        if let eta = workflow.progress.etaSeconds {
            parts.append(String(format: text.etaFormat, durationText(eta)))
        }
        return parts.isEmpty ? activeStageTitle : parts.joined(separator: " · ")
    }

    // MARK: - Completion View (Plan B)

    private var completionView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.complete)
                        .font(.system(size: 12.5, weight: .bold))
                    if let file = workflow.completedFile {
                        Text(file.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }

            qualityFallbackNotice

            ForEach(workflow.warnings, id: \.self) { warning in
                Label(text.message(for: warning), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let file = workflow.completedFile {
                    Button {
                        NSWorkspace.shared.open(file)
                    } label: {
                        Label(text.openFile, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        workflow.revealCompletedFile()
                    } label: {
                        Label(text.revealFinder, systemImage: "folder.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Button {
                        workflow.revealCompletedFile()
                    } label: {
                        Label(text.revealFinder, systemImage: "folder.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                }
            }

            Button {
                workflow.downloadAnother()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text(text.downloadAnother)
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Failure & Auxiliary Views

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
                failureRecoveryActions(for: failure)
                if rateLimitHelpExpanded {
                    rateLimitHelpView
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureRecoveryActions(for failure: VideoDownloaderFailure) -> some View {
        let plan = VideoDownloaderFailureRecoveryPolicy.plan(for: failure)
        return VStack(alignment: .leading, spacing: 6) {
            failureRecoveryButton(plan.primary, prominent: true)
            if let secondary = plan.secondary {
                failureRecoveryButton(secondary, prominent: false)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func failureRecoveryButton(_ action: VideoDownloaderFailureRecoveryAction,
                                       prominent: Bool) -> some View {
        if prominent {
            Button {
                performFailureRecoveryAction(action)
            } label: {
                failureRecoveryLabel(action)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        } else {
            Button {
                performFailureRecoveryAction(action)
            } label: {
                failureRecoveryLabel(action)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private func failureRecoveryLabel(_ action: VideoDownloaderFailureRecoveryAction) -> some View {
        let label: (title: String, icon: String) = {
            switch action {
            case .retry:
                return (text.retry, "arrow.clockwise")
            case .configureBrowserCookies:
                return (text.configureBrowserCookies, "key.fill")
            case .openSystemSettings:
                return (text.openSystemSettings, "gearshape.fill")
            case .copyErrorDetails:
                return errorDetailsCopied
                    ? (text.errorDetailsCopied, "checkmark")
                    : (text.copyErrorDetails, "doc.on.doc")
            case .viewHelp:
                return rateLimitHelpExpanded
                    ? (text.hideHelp, "questionmark.circle.fill")
                    : (text.viewHelp, "questionmark.circle")
            }
        }()
        return Label(label.title, systemImage: label.icon)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    private func performFailureRecoveryAction(_ action: VideoDownloaderFailureRecoveryAction) {
        switch action {
        case .retry:
            workflow.retry()
        case .configureBrowserCookies:
            SettingsRouter.shared.requestVideoDownloaderCookies()
            appDelegate()?.openSettingsWindow()
        case let .openSystemSettings(destination):
            switch destination {
            case .fullDiskAccess:
                Permissions.shared.openFullDiskAccessSettings()
            case .automation:
                Permissions.shared.openAutomationSettings()
            }
        case let .copyErrorDetails(details):
            let copied = GeneralPasteboardAccess.shared.sync {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                return pasteboard.setString(details, forType: .string)
            }
            guard copied else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                errorDetailsCopied = true
            }
            postAccessibilityAnnouncement(text.errorDetailsCopied, priority: .medium)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard workflow.failure == .extractorError(details) else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    errorDetailsCopied = false
                }
            }
        case .viewHelp:
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                rateLimitHelpExpanded.toggle()
            }
        }
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
        VideoDownloaderFailureRecoveryPolicy.plan(for: failure).secondary == .viewHelp
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

    private func qualityChipTitle(for height: Int) -> String {
        String(format: text.heightFormat, height)
    }

    private func thumbnailAccessibilityLabel(for media: VideoDownloaderMedia) -> String {
        guard let duration = media.duration else { return text.thumbnail }
        return "\(text.thumbnail), \(text.duration): \(durationText(duration))"
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

    private func handleExitCommand() {
        switch workflow.phase {
        case .settingUp, .downloading, .finalizing:
            workflow.cancelActiveOperation()
        case .cancelling:
            break
        default:
            onClose?()
        }
    }

    private func announceStatus(for phase: VideoDownloaderPhase) {
        let announcement: String?
        let priority: NSAccessibilityPriorityLevel
        switch phase {
        case .downloading:
            announcement = text.downloading
            priority = .medium
        case .finalizing:
            announcement = text.finalizing
            priority = .medium
        case .cancelling:
            announcement = text.cancelling
            priority = .medium
        case .completed:
            announcement = text.complete
            priority = .high
        case .failed:
            announcement = workflow.failure.map { text.message(for: $0) } ?? text.failureTitle
            priority = .high
        case .cancelled:
            announcement = text.cancelled
            priority = .medium
        default:
            announcement = nil
            priority = .medium
        }
        guard let announcement else { return }
        postAccessibilityAnnouncement(announcement, priority: priority)
    }

    private func postAccessibilityAnnouncement(_ announcement: String,
                                               priority: NSAccessibilityPriorityLevel) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: priority.rawValue,
            ]
        )
    }
}

// MARK: - Dependency Card

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
        workflow.phase == .settingUp || workflow.isCancellingSetup
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
            VStack(alignment: .leading, spacing: 6) {
                DisclosureGroup(isExpanded: detailsBinding) {
                    dependencyDetails
                } label: {
                    dependencySummary
                }
                dependencyAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var dependencyAction: some View {
        if workflow.terminalSetupPending {
            Button(text.checkDependencies) { workflow.checkDependencies() }
                .controlSize(.small)
        } else if !workflow.missingTools.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: text.missingToolsFormat, missingToolNames))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(VideoDownloaderDependencySupport.brewPath() == nil
                       ? text.setUpDownloader : text.installMissingTools) {
                    workflow.setupDependencies()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!workflow.canSetupDependencies)
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
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Settings View

struct VideoDownloaderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var workflow = VideoDownloaderWorkflow.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var settingsRouter = SettingsRouter.shared
    @AppStorage(DefaultsKey.panelUtilityVideoDownloader) private var showInPanel = true
    @AppStorage(DefaultsKey.videoDownloaderUseBrowserCookies) private var useBrowserCookies = false
    @AppStorage(DefaultsKey.videoDownloaderCookiesBrowser) private var cookiesBrowser = "safari"
    @FocusState private var browserCookiesFocused: Bool

    private var text: VideoDownloaderStrings { FeatureStrings.videoDownloader(l10n.language) }

    var body: some View {
        Form {
            Section {
                Toggle(text.showInPanel, isOn: $showInPanel)
            } header: {
                Text(text.settingsGeneral)
            } footer: {
                Text(text.settingsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(text.downloadLocation) {
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
                }
                Button(text.resetDownloads) { workflow.resetDestination() }
                    .controlSize(.small)
            }
            Section {
                Toggle(text.useCookies, isOn: $useBrowserCookies)
                    .focused($browserCookiesFocused)
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
            } header: {
                Text(text.browserAccess)
            }
            Section {
                VideoDownloaderDependencyCard(alwaysShow: true)
            } footer: {
                Text(text.usageNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(text.pageTitle)
        .onAppear {
            workflow.prepareForUse()
            revealBrowserCookiesIfRequested()
        }
        .onChange(of: settingsRouter.videoDownloaderCookiesRequested) { _, requested in
            if requested { revealBrowserCookiesIfRequested() }
        }
        .padding()
    }

    private func revealBrowserCookiesIfRequested() {
        guard settingsRouter.consumeVideoDownloaderCookiesRequest() else { return }
        DispatchQueue.main.async { browserCookiesFocused = true }
    }

    private func chooseDestination() {
        VideoDownloaderDestinationPicker.present(for: workflow)
    }
}
#endif
