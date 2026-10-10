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
    @State private var viewerID = UUID()
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
                service.beginViewing(viewerID)
            }
            .onDisappear {
                isRemovingSources = false
                service.endViewing(viewerID)
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

            Toggle(text.autoAppearance, isOn: Binding(
                get: { service.autoAppearanceEnabled },
                set: { service.setAutoAppearanceEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            if service.autoAppearanceEnabled {
                appearanceSlotsRow
            }

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

    private var appearanceSlotsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                slotCard(mode: .light,
                         slot: service.lightSlot,
                         title: text.lightModeTitle,
                         systemImage: "sun.max.fill",
                         isActive: !service.systemIsDark)
                slotCard(mode: .dark,
                         slot: service.darkSlot,
                         title: text.darkModeTitle,
                         systemImage: "moon.fill",
                         isActive: service.systemIsDark)
            }
            Text(text.appearanceHint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func slotCard(mode: WallpaperSupport.AppearanceMode,
                          slot: WallpaperSupport.AppearanceSlot?,
                          title: String,
                          systemImage: String,
                          isActive: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 32, height: 24)
                if let slot {
                    SlotThumbnailView(url: slot.previewURL, epoch: service.thumbEpoch)
                        .frame(width: 32, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: 9))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    Text(title)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                }
                Text(slot?.title ?? text.chooseImage)
                    .font(.system(size: 10))
                    .foregroundStyle(slot == nil ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if slot != nil {
                Button {
                    service.clearSlot(for: mode)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(text.clearSlot)
                .accessibilityLabel(text.clearSlot)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(isActive ? 0.14 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    slot == nil
                        ? Color.secondary.opacity(0.25)
                        : (isActive ? Color.accentColor.opacity(0.6) : Color.clear),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let slot {
                service.applySlot(slot)
            } else {
                service.pickImageForSlot(mode)
            }
        }
        .help(slot == nil ? text.chooseImage : title)
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
                            isLightSlot: service.lightSlot?.id == entry.id,
                            isDarkSlot: service.darkSlot?.id == entry.id,
                            showsAppearanceBadges: service.autoAppearanceEnabled && !isRemovingSources,
                            thumbEpoch: service.thumbEpoch,
                            height: Self.thumbHeight,
                            showsRemoveBadge: isRemovingSources && entry.source == .own,
                            appliesEnabled: !isRemovingSources && !service.isApplying,
                            removeLabel: text.removeAdded,
                            setLightLabel: text.setForLightMode,
                            setDarkLabel: text.setForDarkMode,
                            onSetLight: { service.setSlot(for: .light, entry: entry) },
                            onSetDark: { service.setSlot(for: .dark, entry: entry) }
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
    var isLightSlot = false
    var isDarkSlot = false
    var showsAppearanceBadges = false
    let thumbEpoch: Int
    var height: CGFloat = 54
    var showsRemoveBadge = false
    var appliesEnabled = true
    var removeLabel = ""
    var setLightLabel = ""
    var setDarkLabel = ""
    var onSetLight: (() -> Void)? = nil
    var onSetDark: (() -> Void)? = nil
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
            .contextMenu {
                if let onSetLight {
                    Button(action: onSetLight) {
                        Label(setLightLabel, systemImage: "sun.max")
                    }
                }
                if let onSetDark {
                    Button(action: onSetDark) {
                        Label(setDarkLabel, systemImage: "moon")
                    }
                }
            }

            if showsAppearanceBadges {
                HStack(spacing: 3) {
                    if let onSetLight {
                        appearanceButton(
                            systemImage: isLightSlot ? "sun.max.fill" : "sun.max",
                            isActive: isLightSlot,
                            activeColor: .orange,
                            label: setLightLabel,
                            action: onSetLight
                        )
                    }
                    if let onSetDark {
                        appearanceButton(
                            systemImage: isDarkSlot ? "moon.fill" : "moon",
                            isActive: isDarkSlot,
                            activeColor: Color(nsColor: .systemIndigo),
                            label: setDarkLabel,
                            action: onSetDark
                        )
                    }
                }
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

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

    private func appearanceButton(
        systemImage: String,
        isActive: Bool,
        activeColor: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? activeColor : Color.black.opacity(0.55))
                    .frame(width: 18, height: 18)
                if isActive {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                        .frame(width: 18, height: 18)
                }
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct SlotThumbnailView: View {
    let url: URL
    let epoch: Int
    @State private var image: NSImage?

    private var taskID: String { "\(url.path)#\(epoch)" }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .onAppear {
            if image == nil, let cached = WallpaperThumbnailCache.image(for: url) {
                image = cached
            }
        }
        .task(id: taskID) {
            let gen = WallpaperThumbnailCache.snapshotGeneration()
            if let cached = WallpaperThumbnailCache.image(for: url) {
                image = cached
                return
            }
            let loaded = await WallpaperThumbnailCache.load(url: url, generation: gen)
            guard !Task.isCancelled,
                  WallpaperThumbnailCache.matchesGeneration(gen)
            else { return }
            image = loaded
        }
    }
}
