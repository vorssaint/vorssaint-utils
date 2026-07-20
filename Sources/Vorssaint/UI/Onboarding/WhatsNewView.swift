// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVKit
import SwiftUI

/// Shown once, automatically, to a user who skipped one or more releases between
/// updates (e.g. 3.0.2 → 3.0.5), so the changes they missed — not only the
/// current version — are surfaced. Clean installs, single-step updates and
/// normal relaunches never see it.
struct WhatsNewView: View {
    let releases: [ReleaseNotes]
    var onClose: () -> Void
    var onDontShowAgain: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                ReleaseNotesContent(releases: releases)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(l10n.s.tabReleaseNotes)
                .font(.system(size: 22, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        HStack {
            Button(l10n.s.whatsNewDontShowAgain) {
                onDontShowAgain()
            }
            Spacer()
            Button(l10n.s.menuClose) {
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

/// Pre-install preview window content: shows the next version's full changelog —
/// the same notes that ship with the release — so the user can decide before any
/// download starts. Opened from both the Settings install button and the menu
/// panel's update banner. Reuses `ReleaseNotesContent`.
struct UpdatePreviewView: View {
    let version: String
    let notes: String?
    var onUpdate: () -> Void
    var onCancel: () -> Void

    @ObservedObject private var l10n = L10n.shared

    private var release: ReleaseNotes {
        // The release body is the changelog section without its `## [..]` header;
        // synthesize one so the existing parser can structure it.
        let body = ReleaseNotes.inAppUpdateNotes(from: notes) ?? ""
        return ReleaseNotes.notes(for: version, changelog: "## [\(version)]\n\n" + body)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l10n.s.tabReleaseNotes)
                    .font(.system(size: 22, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                ReleaseNotesContent(releases: [release])
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
            }

            Divider()

            HStack {
                Button(l10n.s.uninstallerCancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(l10n.s.updateInstallButton) { onUpdate() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 640, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct UpdateShowcaseIntroView: View {
    var onClose: () -> Void

    @StateObject private var mediaLoader = UpdateShowcaseMediaLoader()
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL
    @State private var step: Step = .demo

    private enum Step {
        case demo
        case support
    }

    var body: some View {
        VStack(spacing: 0) {
            if step == .demo {
                showcaseStep
            } else {
                supportStep
            }
        }
        .frame(width: 680, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { mediaLoader.load() }
        .onDisappear {
            mediaLoader.cancel()
            mediaLoader.cleanupCache()
        }
    }

    private var showcaseStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(l10n.s.updateShowcaseTitle)
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(l10n.s.updateShowcaseMessage)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520)
                }
                .padding(.top, 2)

                UpdateShowcaseMediaSurface(state: mediaLoader.state)
                    .frame(width: 592, height: 369)
                    .clipped()
                    .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            HStack {
                Button(l10n.s.supportIntroLaterButton) {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(l10n.s.obContinue) {
                    step = .support
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    private var supportStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            supportContent
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                Button(l10n.s.supportIntroLaterButton) {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding(16)
        }
    }

    private var supportContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.spaceGradient)
                    .frame(width: 74, height: 74)
                Image(systemName: "heart.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(l10n.s.supportIntroTitle)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(l10n.s.supportIntroMessage)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430)

            HStack(spacing: 10) {
                Button {
                    openURL(AppInfo.repositoryURL)
                } label: {
                    Label(l10n.s.supportIntroStarButton, systemImage: "star.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openURL(AppInfo.donateURL)
                } label: {
                    Label(l10n.s.supportIntroCoffeeButton, systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Text(l10n.s.donateThanks)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }
}

/// A one-time note for the launch after update, separate from release notes.
struct UpdateSupportIntroView: View {
    var onFinish: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL
    @State private var step: SupportUpdateIntroStep
    @State private var isMovingForward = true
    @State private var copiedCommand: String?

    init(initialStep: SupportUpdateIntroStep = .homebrew,
         onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if step == .homebrew {
                    homebrewContent
                        .transition(pageTransition)
                } else if step == .community {
                    communityContent
                        .transition(pageTransition)
                } else {
                    supportContent
                        .transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 34)
            .clipped()

            Divider()

            footer
        }
        .frame(width: 560, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: isMovingForward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private func move(to destination: SupportUpdateIntroStep, forward: Bool) {
        isMovingForward = forward
        withAnimation(.easeInOut(duration: 0.3)) {
            step = destination
        }
    }

    private var homebrewContent: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, .yellow],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 74, height: 74)
                    .shadow(color: .orange.opacity(0.24), radius: 10, y: 4)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(Color.green)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 3)
                    }
                    .offset(x: 4, y: 4)
            }

            Text(l10n.s.homebrewOfficialIntroTitle)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(l10n.s.homebrewOfficialIntroMessage)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)

            commandCard(label: l10n.s.homebrewOfficialIntroInstallLabel,
                        command: SupportUpdateIntroInfo.installCommand)

            VStack(spacing: 4) {
                Text(l10n.s.homebrewOfficialIntroMigrationTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(l10n.s.homebrewOfficialIntroMigrationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            commandCard(label: nil, command: SupportUpdateIntroInfo.migrationCommand)
        }
        .padding(.vertical, 16)
    }

    private func commandCard(label: String?, command: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(command)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copy(command)
                } label: {
                    Label(l10n.s.homebrewOfficialIntroCopyButton,
                          systemImage: copiedCommand == command ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: 450)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedCommand = command
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedCommand == command { copiedCommand = nil }
        }
    }

    private var communityContent: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 74, height: 74)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                XLogoShape()
                    .fill(Color.white, style: FillStyle(eoFill: true))
                    .frame(width: 36, height: 36)
            }

            Text(l10n.s.communityIntroTitle)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(l10n.s.communityIntroMessage)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)

            Button {
                openURL(AppInfo.communityURL)
            } label: {
                HStack(spacing: 8) {
                    XLogoShape()
                        .fill(Color.white, style: FillStyle(eoFill: true))
                        .frame(width: 13, height: 13)
                    Text(l10n.s.communityIntroFollowButton)
                }
            }
            .buttonStyle(XFollowButtonStyle())
            .padding(.top, 4)

            Text(AppInfo.communityURL.absoluteString
                .replacingOccurrences(of: "https://", with: ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private var supportContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.spaceGradient)
                    .frame(width: 74, height: 74)
                Image(systemName: "heart.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(l10n.s.supportIntroTitle)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(l10n.s.supportIntroMessage)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430)

            HStack(spacing: 10) {
                Button {
                    openURL(AppInfo.repositoryURL)
                } label: {
                    Label(l10n.s.supportIntroStarButton, systemImage: "star.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openURL(AppInfo.donateURL)
                } label: {
                    Label(l10n.s.supportIntroCoffeeButton, systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Text(l10n.s.donateThanks)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private var footer: some View {
        HStack {
            if let previous = step.previous {
                Button(l10n.s.obBack) {
                    move(to: previous, forward: false)
                }
            }
            Spacer()
            if let next = step.next {
                Button(l10n.s.obContinue) {
                    move(to: next, forward: true)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(l10n.s.supportIntroDoneButton) {
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(16)
    }
}

/// The X (Twitter) logo as a vector path in a 24x24 design box, scaled to the
/// given rect. Fill with `FillStyle(eoFill: true)` so the inner slash cuts out.
struct XLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * scale
        let originY = rect.midY - 12 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        var path = Path()
        path.move(to: point(18.244, 2.25))
        path.addLine(to: point(21.552, 2.25))
        path.addLine(to: point(14.325, 10.51))
        path.addLine(to: point(22.827, 21.75))
        path.addLine(to: point(16.17, 21.75))
        path.addLine(to: point(10.956, 14.933))
        path.addLine(to: point(4.99, 21.75))
        path.addLine(to: point(1.68, 21.75))
        path.addLine(to: point(9.41, 12.915))
        path.addLine(to: point(1.254, 2.25))
        path.addLine(to: point(8.08, 2.25))
        path.addLine(to: point(12.793, 8.481))
        path.closeSubpath()
        path.move(to: point(17.083, 19.77))
        path.addLine(to: point(18.916, 19.77))
        path.addLine(to: point(7.084, 4.126))
        path.addLine(to: point(5.117, 4.126))
        path.closeSubpath()
        return path
    }
}

/// X-branded call to action: white label on a black capsule, readable in both
/// appearances thanks to the faint outline.
private struct XFollowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule(style: .continuous))
    }
}

/// Renders one or more parsed release-note versions, each with a prominent
/// version header and the Added / Changed / Fixed sections, separated by a
/// divider so the newest update is easy to tell apart from older ones (the
/// newest is tinted with the accent colour). Shared by the What's New window and
/// the pre-install update preview so both look identical.
struct ReleaseNotesContent: View {
    let releases: [ReleaseNotes]

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(releases.enumerated()), id: \.offset) { index, release in
                if index > 0 {
                    Divider().padding(.vertical, 18)
                }
                releaseBlock(release, isLatest: index == 0)
            }
        }
    }

    private func releaseBlock(_ release: ReleaseNotes, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("v\(release.version)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isLatest ? Color.accentColor : .primary)
                if let date = release.date {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if release.sections.isEmpty {
                fallbackNote
            } else {
                ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
                    releaseSection(section)
                }
            }
        }
    }

    private var fallbackNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, alignment: .center)
            Text(l10n.s.obWhatsNewFallback)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseSection(_ section: ReleaseNoteSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if !section.title.isEmpty {
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                releaseItem(item, sectionTitle: section.title)
            }
        }
    }

    @ViewBuilder
    private func releaseItem(_ item: ReleaseNoteItem, sectionTitle: String) -> some View {
        switch item {
        case let .paragraph(text):
            Text(text)
                .font(.system(size: 12.8))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: iconName(for: sectionTitle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, alignment: .center)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .image(image):
            if let nsImage = releaseNoteImage(image) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .accessibilityLabel(image.alt)
                    .padding(.leading, 27)
            }
        }
    }

    private func releaseNoteImage(_ image: ReleaseNoteImage) -> NSImage? {
        var path = image.path
        if let resourcesRange = path.range(of: "Resources/") {
            path = String(path[resourcesRange.lowerBound...])
        }
        if path.hasPrefix("Resources/") {
            path.removeFirst("Resources/".count)
        }
        let nsPath = path as NSString
        let ext = nsPath.pathExtension
        let name = (nsPath.deletingPathExtension as NSString).lastPathComponent
        let directory = nsPath.deletingLastPathComponent
        guard !name.isEmpty, !ext.isEmpty else { return nil }
        let subdirectory = directory.isEmpty || directory == "." ? nil : directory
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: ext,
                                        subdirectory: subdirectory) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func iconName(for title: String) -> String {
        switch title.lowercased() {
        case "added": return "plus.circle.fill"
        case "changed": return "slider.horizontal.3"
        case "fixed": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
}

private struct UpdateShowcaseMediaSurface: View {
    let state: UpdateShowcaseMediaLoader.State

    @ObservedObject private var l10n = L10n.shared
    @State private var gifReloadID = UUID()

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                switch state {
                case .idle, .loading:
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(l10n.s.homebrewLoading)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                case let .ready(url):
                    if url.pathExtension.lowercased() == "gif" {
                        AnimatedFileGIF(url: url)
                            .id(gifReloadID)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(10)
                    } else {
                        ControlledVideoView(url: url)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(10)
                    }
                case .failed:
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(l10n.s.updateShowcaseUnavailable)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )

            if case let .ready(url) = state,
               url.pathExtension.lowercased() == "gif" {
                HStack {
                    Button {
                        gifReloadID = UUID()
                    } label: {
                        Label(l10n.s.updateShowcaseRestart, systemImage: "gobackward")
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(height: 28)
            }
        }
    }
}

private struct AnimatedFileGIF: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = ShowcaseAnimatedImageView()
        view.imageAlignment = .alignCenter
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        view.image = NSImage(contentsOf: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var url: URL?
    }
}

private final class ShowcaseAnimatedImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private struct ControlledVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            let player = AVPlayer(url: url)
            player.isMuted = true
            view.player = player
            player.play()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var url: URL?
    }
}
