// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The one-time tour shown after a headline update. Every page belongs to the
/// pinned release and uses a native illustration, so it never ships personal
/// content or gets stale when another part of the interface changes.
struct UpdateHighlightsView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var index = 0
    let onFinish: () -> Void

    private var s: Strings { l10n.s }
    private var screenshot: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }
    private var clipboard: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private enum Layout {
        static let width: CGFloat = 600
        static let pageHeight: CGFloat = 414
        static let height: CGFloat = 552
        static let captionLines = 2
    }

    private struct Highlight: Identifiable {
        let id: String
        let imageName: String
        let symbol: String
        let title: String
        let caption: String
        let actionLabel: String
        let action: () -> Void
    }

    private var highlights: [Highlight] {
        var pages: [Highlight] = []
        if AppFeature.screenshot.isAvailable {
            pages.append(Highlight(
                id: "capture-palette",
                imageName: "highlights-capture",
                symbol: "camera.viewfinder",
                title: screenshot.screenCaptureTitle,
                caption: s.highlightsCaptionCapturePalette,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(AppFeature.screenshot.settingsDestination) }))
        }
        if AppFeature.clipboardHistory.isAvailable {
            pages.append(Highlight(
                id: "clipboard-palette",
                imageName: "highlights-clipboard",
                symbol: "doc.on.clipboard",
                title: s.highlightsTitleClipboardRedesign,
                caption: s.highlightsCaptionClipboardRedesign,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(AppFeature.clipboardHistory.settingsDestination) }))
        }
        return pages
    }

    var body: some View {
        let pages = highlights
        let clamped = min(index, max(0, pages.count - 1))
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text(s.highlightsTitle)
                    .font(.title3.weight(.bold))
                Text("Vorssaint \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 23)
            .padding(.bottom, 13)

            ZStack {
                if pages.indices.contains(clamped) {
                    page(pages[clamped])
                        .id(pages[clamped].id)
                        .transition(.opacity)
                }
            }
            .frame(height: Layout.pageHeight)
            .animation(.easeInOut(duration: 0.18), value: clamped)

            ZStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { dot in
                        Circle()
                            .fill(dot == clamped ? Color.accentColor : Color.primary.opacity(0.18))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)

                HStack {
                    if clamped > 0 {
                        Button(s.obBack) { index = clamped - 1 }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(s.highlightsSeeAll) { openSettings(.releaseNotes) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(s.obContinue) {
                        if clamped >= pages.count - 1 {
                            onFinish()
                        } else {
                            index = clamped + 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(width: Layout.width, height: Layout.height)
    }

    private func page(_ highlight: Highlight) -> some View {
        VStack(spacing: 12) {
            UpdateHighlightArtwork(imageName: highlight.imageName, fallbackSymbol: highlight.symbol)
                .frame(width: 500, height: 268)
                .accessibilityHidden(true)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

            VStack(spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: highlight.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(highlight.title)
                        .font(.title3.weight(.semibold))
                }
                Text(highlight.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(Layout.captionLines)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(highlight.actionLabel) { highlight.action() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
    }

    private func openSettings(_ destination: FeatureSettingsDestination) {
        SettingsRouter.shared.request(destination)
        appDelegate()?.openSettingsWindow()
    }

    private func openSettings(_ page: SettingsPage) {
        SettingsRouter.shared.page = page
        appDelegate()?.openSettingsWindow()
    }
}

private struct UpdateHighlightArtwork: View {
    let imageName: String
    let fallbackSymbol: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18),
                         Color.purple.opacity(0.08),
                         Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            if let image = asset(imageName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
                    .padding(14)
            } else {
                ZStack {
                    Theme.spaceGradient
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func asset(_ name: String) -> NSImage? {
        let extensions = ["png", "jpg", "jpeg"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Images")
                ?? Bundle.main.url(forResource: name, withExtension: ext) {
                if let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }
        for ext in extensions {
            let direct = URL(fileURLWithPath: "Resources/Images/\(name).\(ext)")
            if let image = NSImage(contentsOf: direct) {
                return image
            }
        }
        return nil
    }
}
