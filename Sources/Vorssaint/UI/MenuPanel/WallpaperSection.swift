// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import SwiftUI

/// Wallpaper tab in the menu panel.
struct WallpaperSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = WallpaperService.shared
    @State private var page = 1
    @State private var isRemovingSources = false
    var collapsible = true

    private var text: WallpaperFeatureStrings {
        FeatureStrings.wallpaper(l10n.language)
    }

    private var allItems: [WallpaperSupport.Entry] { service.visibleEntries }

    private var pageCount: Int {
        WallpaperSupport.pageCount(itemCount: allItems.count)
    }

    private var currentPage: Int {
        WallpaperSupport.clampedPage(page, itemCount: allItems.count)
    }

    private var pageItems: [WallpaperSupport.Entry] {
        WallpaperSupport.pageSlice(allItems, page: currentPage)
    }

    private var canManageSources: Bool {
        !service.ownSources.isEmpty
    }

    var body: some View {
        PanelSection(.wallpaper,
                     title: text.pageTitle,
                     collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                controls
                if isRemovingSources, !service.removableChipSources.isEmpty {
                    sourceRemoveStrip
                }
                gallery
                pager
                if service.isDownloading {
                    Text(text.downloading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = service.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .onAppear {
                // own folders can change on disk; keep Apple catalog cache
                service.refresh(forceAppleRescan: false)
            }
            .onDisappear {
                isRemovingSources = false
                service.cancelThumbs()
            }
            .onChange(of: currentPage) { _, newPage in
                service.preparePageThumbs(for: service.filter, around: newPage)
            }
            .onChange(of: service.filter) { _, _ in
                page = 1
            }
            .onChange(of: service.entries.count) { _, _ in
                page = WallpaperSupport.clampedPage(page, itemCount: allItems.count)
            }
            .onChange(of: service.ownSources.count) { _, count in
                if count == 0 {
                    isRemovingSources = false
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(
                get: { service.filter },
                set: { newValue in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        service.setFilter(newValue)
                    }
                }
            )) {
                Text(text.filterAll).tag(WallpaperSupport.Filter.all)
                Text(text.filterOwn).tag(WallpaperSupport.Filter.own)
                Text(text.filterApple).tag(WallpaperSupport.Filter.apple)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Toggle(text.applyAllDisplays, isOn: Binding(
                get: { service.applyAllDisplays },
                set: { service.applyAllDisplays = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack(spacing: 8) {
                Button(text.addImage) { service.addImages() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRemovingSources)
                Button(text.addFolder) { service.addFolder() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRemovingSources)
                if canManageSources || isRemovingSources {
                    Button(isRemovingSources ? text.doneRemoving : text.removeAdded) {
                        isRemovingSources.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // folders + unreachable + orphan file bookmarks
    private var sourceRemoveStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(service.removableChipSources) { source in
                    HStack(spacing: 6) {
                        Image(systemName: source.isReachable
                              ? (source.isFolder ? "folder" : "photo")
                              : "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(source.title)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            service.removeOwnSource(source)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .help(text.removeAdded)
                        .accessibilityLabel(text.removeAdded)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                    )
                }
            }
        }
    }

    // with several pages every page keeps the full 3x8 height so paging does
    // not resize the panel; a single page only takes the rows it fills
    private static let thumbHeight: CGFloat = 54
    private static let gridSpacing: CGFloat = 8
    private static let columnCount = 3
    private static var rowCount: Int {
        (WallpaperSupport.pageSize + columnCount - 1) / columnCount
    }
    private static func galleryHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * thumbHeight + CGFloat(max(0, rows - 1)) * gridSpacing
    }
    private var galleryRows: Int {
        if pageCount > 1 { return Self.rowCount }
        if allItems.isEmpty { return 2 }
        return (allItems.count + Self.columnCount - 1) / Self.columnCount
    }

    @ViewBuilder
    private var gallery: some View {
        ZStack(alignment: .topLeading) {
            if allItems.isEmpty {
                Group {
                    if service.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Self.gridSpacing),
                    GridItem(.flexible(), spacing: Self.gridSpacing),
                    GridItem(.flexible(), spacing: Self.gridSpacing),
                ], spacing: Self.gridSpacing) {
                    ForEach(pageItems) { entry in
                        WallpaperThumbButton(
                            entry: entry,
                            isApplied: service.appliedPath == entry.imageURL.path,
                            thumbEpoch: service.thumbEpoch,
                            height: Self.thumbHeight,
                            showsRemoveBadge: isRemovingSources && entry.source == .own,
                            appliesEnabled: !isRemovingSources && !service.isApplying,
                            removeLabel: text.removeAdded
                        ) {
                            service.apply(entry)
                        } onRemove: {
                            service.removeOwnEntry(entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity,
               minHeight: Self.galleryHeight(rows: galleryRows),
               maxHeight: Self.galleryHeight(rows: galleryRows),
               alignment: .topLeading)
    }

    private var pager: some View {
        HStack(spacing: 12) {
            if pageCount > 1 {
                Button {
                    page = max(1, currentPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(currentPage <= 1)
                .help(text.previousPage)
                .accessibilityLabel(text.previousPage)

                Text("\(currentPage) / \(pageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    page = min(pageCount, currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(currentPage >= pageCount)
                .help(text.nextPage)
                .accessibilityLabel(text.nextPage)
            }

            Spacer(minLength: 8)
            Button(text.openSystemSettings) {
                service.openSystemWallpaperSettings()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(height: 22)
    }


    private var emptyMessage: String {
        switch service.filter {
        case .all: return text.emptyAll
        case .own: return text.emptyOwn
        case .apple: return text.emptyApple
        }
    }
}

private struct WallpaperThumbButton: View {
    let entry: WallpaperSupport.Entry
    let isApplied: Bool
    let thumbEpoch: Int
    var height: CGFloat = 54
    var showsRemoveBadge = false
    var appliesEnabled = true
    var removeLabel = ""
    let action: () -> Void
    var onRemove: () -> Void = {}
    @State private var image: NSImage?

    private var previewPath: String { entry.previewURL.path }
    // epoch in id so a generation bump restarts load (same path can stay blank otherwise)
    private var taskID: String { "\(previewPath)#\(thumbEpoch)" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isApplied ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .disabled(!appliesEnabled)
            .help(entry.title)
            .accessibilityLabel(entry.title)

            if showsRemoveBadge {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 16))
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help(removeLabel)
                .accessibilityLabel(removeLabel)
            }
        }
        .onAppear {
            if image == nil, let cached = WallpaperThumbnailCache.image(for: entry.previewURL) {
                image = cached
            }
        }
        .task(id: taskID) {
            let gen = WallpaperThumbnailCache.snapshotGeneration()
            if let cached = WallpaperThumbnailCache.image(for: entry.previewURL) {
                image = cached
                return
            }
            let url = entry.previewURL
            let loaded = await WallpaperThumbnailCache.load(url: url, generation: gen)
            guard !Task.isCancelled,
                  WallpaperThumbnailCache.matchesGeneration(gen)
            else { return }
            image = loaded
        }
    }
}
