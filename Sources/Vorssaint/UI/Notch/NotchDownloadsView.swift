// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchDownloadsSettingsControls: View {
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchDownloadsEnabled) private var enabled = false
    private var text: NotchFilesStrings { FeatureStrings.notchFiles(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.downloadsTitle, isOn: $enabled)
                .disabled(!AppFeature.notchDownloads.isAvailable)
            Text(text.downloadsHint).font(.caption).foregroundStyle(.secondary)
            if downloads.folderUnavailable {
                Text(text.folderUnavailable).font(.caption).foregroundStyle(.orange)
            } else if let name = downloads.folderName {
                Label(name, systemImage: "folder").font(.caption).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button(text.chooseFolder, action: downloads.chooseFolder)
                if downloads.folderName != nil || downloads.folderUnavailable {
                    Button(text.clearFolder, action: downloads.forgetFolder)
                }
            }.controlSize(.small)
        }
        .onChange(of: enabled) { NotchService.shared.syncWithPreferences() }
    }
}

struct NotchDownloadsView: View {
    let size: CGSize
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchDownloadsEnabled) private var enabled = false
    private var text: NotchFilesStrings { FeatureStrings.notchFiles(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            if !enabled || downloads.folderName == nil || downloads.folderUnavailable {
                NotchDownloadsSettingsControls()
            } else {
                HStack {
                    Label(downloads.folderName ?? text.downloadsTitle, systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Menu {
                        Button(text.chooseFolder, action: downloads.chooseFolder)
                        Button(text.clearFolder, action: downloads.forgetFolder)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(FeatureStrings.notch(l10n.language).events)
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(height: 20)
                if downloads.items.isEmpty {
                    NotchEmptyView(symbol: "arrow.down.circle", message: text.waiting)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(downloads.items) { item in
                                downloadCard(item)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func downloadCard(_ item: NotchDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(item.completed ? .green : .white)
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.completed {
                    NotchIconButton(symbol: "folder", title: l10n.s.mediaOpenInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    if AppFeature.shelf.isAvailable {
                        NotchIconButton(symbol: "tray.and.arrow.down", title: FeatureStrings.notch(l10n.language).files) {
                            _ = ShelfService.shared.addFiles([item.url])
                        }
                    }
                } else if let fraction = item.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption).monospacedDigit()
                }
            }
            if item.completed {
                Text(text.saved).font(.caption).foregroundStyle(.secondary)
            } else {
                if let fraction = item.fraction {
                    NotchMeter(value: fraction)
                } else if item.active {
                    ProgressView().controlSize(.small)
                }
                HStack {
                    Text(item.active ? text.inProgress : "")
                    Spacer()
                    if let bytes = item.receivedBytes, bytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    } else if item.fraction == nil {
                        Text(text.totalUnknown)
                    }
                }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipped()
        .accessibilityElement(children: .contain)
    }
}

struct NotchDownloadStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var l10n = L10n.shared

    /// The arrow keeps the shared gap from the top and bottom edges too.
    private var iconSize: CGFloat {
        min(17, service.geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2)
    }
    private var iconInset: CGFloat {
        service.geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
    }

    var body: some View {
        let item = downloads.items.first { $0.active && !$0.completed }
        Button { service.open(.downloads) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    if service.geometry.compactActivityWingWidth >= 40 {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: iconSize))
                        if service.geometry.compactActivityWingWidth >= 94 {
                            Text(item?.name ?? FeatureStrings.notchFiles(l10n.language).downloadsTitle)
                                .font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .padding(.leading, service.geometry.compactActivityWingWidth >= 40 ? iconInset : 0)
                .padding(.trailing, 4)
                // Each wing anchors to its own edge, so the silhouette's curve
                // decides the margin instead of the content's own width.
                .frame(width: service.geometry.compactActivityWingWidth, alignment: .leading).clipped()
                Color.clear.frame(width: service.geometry.compactActivityCameraGap)
                HStack {
                    Spacer(minLength: 0)
                    if service.geometry.compactActivityWingWidth >= 36 {
                        if let fraction = item?.fraction {
                            Text(fraction, format: NotchDownloadSupport.percentFormat(l10n.language))
                                .font(.system(size: NotchDownloadSupport.percentSize, weight: .medium))
                                .monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(NotchDownloadSupport.percentMinimumScale)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .padding(.trailing, service.geometry.compactActivityWingWidth >= 36
                                    ? NotchDownloadSupport.percentInset(in: service.geometry) : 0)
                .frame(width: service.geometry.compactActivityWingWidth, alignment: .trailing).clipped()
            }
            .frame(height: service.geometry.compactActivityContentHeight)
            .padding(.horizontal, service.geometry.compactActivityHorizontalPadding)
            .padding(.top, service.geometry.compactActivityTopPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item?.name ?? FeatureStrings.notchFiles(l10n.language).downloadsTitle)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}
