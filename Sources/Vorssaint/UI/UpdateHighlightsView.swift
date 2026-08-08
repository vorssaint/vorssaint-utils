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
    private var commandBar: CommandBarFeatureStrings {
        FeatureStrings.commandBar(l10n.language)
    }
    private var diskInstaller: DiskImageInstallerStrings {
        FeatureStrings.diskImageInstaller(l10n.language)
    }
    private var fanControl: FanControlFeatureStrings {
        FeatureStrings.fanControl(l10n.language)
    }
    private var windowLayout: WindowLayoutFeatureStrings {
        FeatureStrings.windowLayout(l10n.language)
    }

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
        var pages = [
            Highlight(
                id: "disk-image-installer",
                kind: .installer(diskInstaller, cancelTitle: s.uninstallerCancel),
                symbol: AppFeature.diskImageInstaller.symbolName,
                title: diskInstaller.title,
                caption: diskInstaller.hubDescription,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(.features) }),
        ]
        if AppFeature.windowLayout.isAvailable {
            pages.append(Highlight(
                id: "window-edge-snap",
                kind: .edgeSnap,
                symbol: "rectangle.split.2x1",
                title: windowLayout.edgeSnapEnable,
                caption: windowLayout.edgeSnapCaption,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(.windowLayout) }))
        }
        pages.append(Highlight(
            id: "fan-control",
            kind: .fanControl,
            symbol: AppFeature.fanControl.symbolName,
            title: fanControl.title,
            caption: fanControl.hubDescription,
            actionLabel: s.highlightsConfigure,
            action: { openSettings(.features) }))
        if AppFeature.commandBar.isAvailable {
            pages.append(Highlight(
                id: "command-bar-links",
                kind: .commandLinks(commandBar),
                symbol: AppFeature.commandBar.symbolName,
                title: commandBar.pageTitle,
                caption: commandBar.openInBrowser,
                actionLabel: s.highlightsConfigure,
                action: { openSettings(.commandBar) }))
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
        case installer(DiskImageInstallerStrings, cancelTitle: String)
        case edgeSnap
        case fanControl
        case commandLinks(CommandBarFeatureStrings)
    }

    let kind: Kind
    @Environment(\.colorScheme) private var colorScheme

    private var markTint: Color {
        colorScheme == .light ? Color(white: 0.03) : .white
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.20),
                         Color.purple.opacity(0.09),
                         Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            switch kind {
            case let .installer(strings, cancelTitle):
                installer(strings: strings, cancelTitle: cancelTitle)
            case .edgeSnap: edgeSnap
            case .fanControl: fanControl
            case let .commandLinks(strings): commandLinks(strings: strings)
            }
        }
    }

    private func installer(strings: DiskImageInstallerStrings,
                           cancelTitle: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.indigo, Color.blue.opacity(0.72)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.promptTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text(String(format: strings.promptBodyFormat, "App"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Spacer()
                    alertButton(cancelTitle, prominent: false)
                    alertButton(strings.installButton, prominent: true)
                }
            }
        }
        .padding(22)
        .frame(width: 440, height: 190)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private func alertButton(_ title: String, prominent: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.primary.opacity(0.08))
            )
    }

    private var edgeSnap: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 400, height: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.13), lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.20))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                }
                .frame(width: 180, height: 190)
                .offset(x: 15, y: 15)

            windowCard
                .frame(width: 184, height: 126)
                .offset(x: 194, y: 47)

            Image(systemName: "cursorarrow")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
                .offset(x: 170, y: 145)
        }
        .frame(width: 400, height: 220)
    }

    private var windowCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(.red.opacity(0.85)).frame(width: 7, height: 7)
                Circle().fill(.yellow.opacity(0.85)).frame(width: 7, height: 7)
                Circle().fill(.green.opacity(0.85)).frame(width: 7, height: 7)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 24)

            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(Color.accentColor.opacity(0.28)).frame(width: 75, height: 7)
                Capsule().fill(Color.primary.opacity(0.13)).frame(height: 6)
                Capsule().fill(Color.primary.opacity(0.10)).frame(width: 118, height: 6)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private var fanControl: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 126, height: 126)
                Circle()
                    .trim(from: 0.08, to: 0.84)
                    .stroke(Color.cyan.opacity(0.75),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 108, height: 108)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 57, weight: .medium))
                    .foregroundStyle(Color.cyan)
            }

            VStack(spacing: 13) {
                fanReading(progress: 0.82, value: "3240")
                fanReading(progress: 0.68, value: "2860")
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                    Text("15:00")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
        .padding(22)
        .frame(width: 410, height: 220)
        .background(card)
    }

    private func fanReading(progress: CGFloat, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "fanblades")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule().fill(Color.cyan.opacity(0.72))
                    .frame(width: 105 * progress)
            }
            .frame(width: 105, height: 7)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func commandLinks(strings: CommandBarFeatureStrings) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                BrandMark(width: 22, tint: markTint)
                    .opacity(0.85)
                    .frame(width: 22, height: 22)
                Text(verbatim: "https://example.com")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "globe")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.85))
                    }
                VStack(alignment: .leading, spacing: 7) {
                    Text(verbatim: "https://example.com")
                        .font(.system(size: 13, weight: .medium))
                    Text(strings.openInBrowser)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            )
            .padding(8)

            Divider()

            HStack(spacing: 5) {
                Image(systemName: "keyboard")
                    .font(.system(size: 8.5))
                Text(GlobalShortcut.saved(for: DefaultsKey.commandBarShortcut,
                                          fallback: .commandBarDefault).displayString)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                Spacer()
                Text("↑↓")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                Image(systemName: "return")
                    .font(.system(size: 8))
                Text("Esc")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 440)
        .background(HUDBackdrop(cornerRadius: 22, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 16, y: 7)
    }

    private var card: some ShapeStyle {
        Color(nsColor: .controlBackgroundColor)
            .shadow(.drop(color: .black.opacity(0.10), radius: 8, y: 3))
    }
}
