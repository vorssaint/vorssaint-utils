// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The one-time tour shown after a headline update. Every page belongs to the
/// pinned release and uses a native illustration, so it never ships personal
/// content or gets stale when another part of the interface changes.
struct UpdateHighlightsView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var index = 0
    @State private var showingSharePrivacy = false
    let onFinish: () -> Void

    private var s: Strings { l10n.s }
    private var screenshot: ScreenshotFeatureStrings { FeatureStrings.screenshot(l10n.language) }
    private var recorder: RecorderFeatureStrings { FeatureStrings.recorder(l10n.language) }
    private var feedback: FeedbackStrings { FeatureStrings.feedback(l10n.language) }

    private enum Layout {
        static let width: CGFloat = 600
        static let pageHeight: CGFloat = 414
        static let height: CGFloat = 552
        static let captionLines = 2
    }

    private struct Highlight: Identifiable {
        let id: String
        let kind: UpdateHighlightArtwork.Kind
        let symbol: String
        let title: String
        let caption: String
        let actionLabel: String
        let action: () -> Void
    }

    private var highlights: [Highlight] {
        var pages: [Highlight] = []
        if AppFeature.screenRecorder.isAvailable {
            pages.append(Highlight(
                id: "recorder",
                kind: .recorder,
                symbol: AppFeature.screenRecorder.symbolName,
                title: recorder.pageTitle,
                caption: recorder.hubDescription,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(.screenRecorder) }))
        }
        if AppFeature.screenshot.isAvailable {
            pages.append(Highlight(
                id: "scrolling-screenshot",
                kind: .scrolling,
                symbol: "arrow.down.to.line",
                title: screenshot.scrollingCaptureTitle,
                caption: screenshot.scrollingCaptureCaption,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(.screenshot) }))
            pages.append(Highlight(
                id: "temporary-links",
                kind: .sharing,
                symbol: "link",
                title: screenshot.shareSectionTitle,
                caption: screenshot.shareCaption,
                actionLabel: s.highlightsTry,
                action: { showingSharePrivacy = true }))
        }
        pages.append(Highlight(
            id: "feedback",
            kind: .feedback,
            symbol: "bubble.left.and.text.bubble.right.fill",
            title: feedback.sectionTitle,
            caption: feedback.sectionCaption,
            actionLabel: feedback.openButton,
            action: { appDelegate()?.openFeedbackWindow(kind: .feature) }))
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
        .sheet(isPresented: $showingSharePrivacy) {
            ScreenshotSharePrivacyView(actionTitle: screenshot.captureButton) {
                ScreenshotService.shared.capture()
            }
        }
    }

    private func page(_ highlight: Highlight) -> some View {
        VStack(spacing: 12) {
            UpdateHighlightArtwork(kind: highlight.kind)
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

    private func openSettings(_ page: SettingsPage) {
        SettingsRouter.shared.page = page
        appDelegate()?.openSettingsWindow()
    }
}

private struct UpdateHighlightArtwork: View {
    enum Kind {
        case recorder, scrolling, sharing, feedback
    }

    let kind: Kind

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.20), Color.purple.opacity(0.09), Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            switch kind {
            case .recorder: recorder
            case .scrolling: scrolling
            case .sharing: sharing
            case .feedback: feedback
            }
        }
    }

    private var recorder: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 13, height: 13)
                Capsule().fill(.primary.opacity(0.12)).frame(width: 105, height: 8)
                Spacer()
                Image(systemName: "mic.fill").foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.78))
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
            HStack(spacing: 8) {
                Capsule().fill(.red.opacity(0.75)).frame(width: 120, height: 7)
                Capsule().fill(.primary.opacity(0.13)).frame(height: 7)
                Image(systemName: "scissors").foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 390, height: 220)
        .background(card)
    }

    private var scrolling: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { cardIndex in
                VStack(alignment: .leading, spacing: 9) {
                    Capsule().fill(Color.accentColor.opacity(0.32)).frame(width: 92, height: 8)
                    ForEach(0..<4, id: \.self) { line in
                        Capsule()
                            .fill(Color.primary.opacity(line == 3 ? 0.09 : 0.16))
                            .frame(width: CGFloat(210 - line * 20), height: 6)
                    }
                }
                .padding(16)
                .frame(width: 280, height: 105, alignment: .topLeading)
                .background(card)
                .offset(y: CGFloat(cardIndex * 49 - 49))
            }
            VStack(spacing: 5) {
                Image(systemName: "chevron.down")
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .offset(x: 178)
        }
    }

    private var sharing: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Capsule().fill(.primary.opacity(0.13)).frame(width: 245, height: 9)
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(card)

            HStack(spacing: 18) {
                duration("1h", selected: false)
                duration("6h", selected: true)
                duration("24h", selected: false)
            }

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Capsule().fill(.primary.opacity(0.12)).frame(width: 150, height: 7)
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 390)
    }

    private func duration(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(width: 64, height: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
    }

    private var feedback: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                feedbackChoice(symbol: "ladybug.fill", selected: false)
                feedbackChoice(symbol: "sparkles", selected: true)
            }
            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(.primary.opacity(0.11)).frame(width: 270, height: 7)
                Capsule().fill(.primary.opacity(0.08)).frame(width: 225, height: 7)
                Capsule().fill(.primary.opacity(0.08)).frame(width: 160, height: 7)
            }
            .padding(17)
            .frame(width: 350, height: 86, alignment: .topLeading)
            .background(card)
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Spacer()
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 330)
        }
    }

    private func feedbackChoice(symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(width: 72, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
    }

    private var card: some ShapeStyle {
        Color(nsColor: .controlBackgroundColor).shadow(.drop(color: .black.opacity(0.10), radius: 8, y: 3))
    }
}
