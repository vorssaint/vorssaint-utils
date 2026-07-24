// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The one-time tour shown right after an update: one page per headline
/// feature, each with a real capture of it working and a button that sets it
/// up or tries it on the spot. New features arrive switched off, so without
/// this window they stay invisible to anyone who never opens Settings.
struct UpdateHighlightsView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var index = 0
    let onFinish: () -> Void

    private var s: Strings { l10n.s }
    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    /// The window is sized by the view, so both axes are declared here and
    /// nothing about the content is allowed to move them: a window whose size
    /// keeps being recomputed while it is on screen makes the layout engine
    /// fight whoever placed it. The numbers come from measuring the tallest
    /// page in all thirteen languages.
    private enum Layout {
        static let width: CGFloat = 600
        static let pageHeight: CGFloat = 406
        static let height: CGFloat = 541
        /// Captions get two lines everywhere; the reserved page height is
        /// built for exactly that.
        static let captionLines = 2
    }

    private struct Highlight: Identifiable {
        let id: String
        let symbol: String
        let imageName: String
        let title: String
        let caption: String
        let actionLabel: String
        let action: () -> Void
    }

    /// The curated pages for the pinned release. Features the user
    /// uninstalled in the hub stay out; their Settings pages are gone too.
    private var highlights: [Highlight] {
        var pages: [Highlight] = []
        if AppFeature.textSnippets.isAvailable {
            pages.append(Highlight(
                id: "snippetlibrary", symbol: AppFeature.textSnippets.symbolName,
                imageName: "highlights-snippetlibrary",
                title: FeatureStrings.snippets(l10n.language).libraryTitle,
                caption: s.highlightsCaptionSnippetLibrary,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(.textSnippets) }))
        }
        if AppFeature.mouseButtonShortcuts.isAvailable {
            pages.append(Highlight(
                id: "mousebuttons", symbol: AppFeature.mouseButtonShortcuts.symbolName,
                imageName: "highlights-mousebuttons",
                title: AppFeature.mouseButtonShortcuts.hubTitle(s, hub: hub),
                caption: AppFeature.mouseButtonShortcuts.hubDescription(hub),
                actionLabel: s.highlightsConfigure,
                action: { openSettings(.mouse) }))
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
            .padding(.top, 24)
            .padding(.bottom, 16)

            // The page area keeps the same height on every page and in every
            // language, so turning a page fades the content instead of
            // resizing the window under it.
            ZStack {
                if pages.indices.contains(clamped) {
                    page(pages[clamped])
                        .id(pages[clamped].id)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.18), value: clamped)
                }
            }
            .frame(height: Layout.pageHeight)

            ZStack {
                // The side buttons have different widths, so the dots sit in
                // their own layer centered on the window, not between them.
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
                        Button(s.highlightsSeeAll) {
                            openSettings(.releaseNotes)
                        }
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
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: Layout.width, height: Layout.height)
    }

    private func page(_ highlight: Highlight) -> some View {
        VStack(spacing: 14) {
            Group {
                if let image = Self.asset(highlight.imageName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    // A release that forgot to ship a capture still gets a
                    // presentable page.
                    ZStack {
                        Theme.spaceGradient
                        Image(systemName: highlight.symbol)
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 480)
                }
            }
            .frame(maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

            VStack(spacing: 5) {
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
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Acting keeps the tour open: the mirror or pad floats above it,
            // and Settings opens next to it, so the remaining pages are never
            // lost to one click.
            Button(highlight.actionLabel) { highlight.action() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
    }

    /// At least one featured item survives in the hub, so the tour has a
    /// page to show. The gate reads this before opening the window.
    static var hasContent: Bool {
        [AppFeature.mouseButtonShortcuts, .textSnippets]
            .contains { $0.isAvailable }
    }

    private static func asset(_ name: String) -> NSImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Images")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    private func openSettings(_ page: SettingsPage) {
        SettingsRouter.shared.page = page
        appDelegate()?.openSettingsWindow()
    }
}
