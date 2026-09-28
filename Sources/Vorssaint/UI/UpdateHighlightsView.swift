// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The release's Dynamic Island demonstration, stored inside the app bundle.
struct UpdateHighlightsView: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var availableSize = NSScreen.pointerVisibleFrame.size
    let onFinish: () -> Void

    private var text: NotchTourStrings { FeatureStrings.notchTour(l10n.language) }
    private var animationURL: URL? {
        Bundle.main.url(forResource: "highlights-notch", withExtension: "gif", subdirectory: "Gifs")
    }

    var body: some View {
        let size = UpdateHighlightsLayout.size(in: availableSize)
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(FeatureStrings.notch(l10n.language).title).font(.title2.weight(.semibold))
                Text(AppInfo.isDeveloperBuild ? text.preview : "Vorssaint \(AppInfo.version)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(height: 42)

            ScrollView {
                VStack(spacing: 16) {
                    Group {
                        if let animationURL {
                            UpdateHighlightsGIF(url: animationURL, animates: !reduceMotion)
                        } else {
                            Image(systemName: "rectangle.topthird.inset.filled")
                                .font(.system(size: 72, weight: .light)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: UpdateHighlightsLayout.artworkHeight(in: size))
                    .clipped()
                    .accessibilityHidden(true)

                    Text(text.caption)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Button(l10n.s.highlightsConfigure) {
                    if !AppFeature.notch.isAvailable {
                        FeatureRuntime.shared.setAvailable([.notch], true)
                    }
                    SettingsRouter.shared.request(AppFeature.notch.settingsDestination)
                    appDelegate()?.openSettingsFromHighlights()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(l10n.s.supportIntroDoneButton, action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(height: 32)
        }
        .frame(maxWidth: 500)
        .padding(24)
        .frame(width: size.width, height: size.height)
    }
}

enum UpdateHighlightsLayout {
    static func size(in available: CGSize) -> CGSize {
        CGSize(width: min(600, max(1, available.width - 32)),
               height: min(660, max(1, available.height - 32)))
    }

    static func artworkHeight(in size: CGSize) -> CGFloat {
        min(400, max(80, size.height - 260))
    }
}

private struct UpdateHighlightsGIF: NSViewRepresentable {
    let url: URL
    let animates: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = animates
        let image = NSImage(contentsOf: url)
        image?.size = NSSize(width: 451, height: 400)
        imageView.image = image
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.subviews.first as? NSImageView)?.animates = animates
    }
}
