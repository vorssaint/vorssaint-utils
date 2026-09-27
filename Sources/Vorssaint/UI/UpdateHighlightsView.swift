// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The release's Dynamic Island demonstration, stored inside the app bundle.
struct UpdateHighlightsView: View {
    @ObservedObject private var l10n = L10n.shared
    let onFinish: () -> Void

    private var text: NotchTourStrings { FeatureStrings.notchTour(l10n.language) }
    private var animationURL: URL? {
        Bundle.main.url(forResource: "highlights-notch", withExtension: "gif", subdirectory: "Gifs")
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(FeatureStrings.notch(l10n.language).title).font(.title2.weight(.semibold))
                Text(AppInfo.isDeveloperBuild ? text.preview : "Vorssaint \(AppInfo.version)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(height: 42)

            Group {
                if let animationURL {
                    UpdateHighlightsGIF(url: animationURL)
                } else {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 72, weight: .light)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 500, height: 400)
            .clipped()
            .accessibilityHidden(true)

            Text(text.caption)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 500, height: 58)

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
            .frame(width: 500, height: 32)
        }
        .padding(24)
        .frame(width: 600, height: 660)
    }
}

private struct UpdateHighlightsGIF: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
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

    func updateNSView(_ view: NSView, context: Context) {}
}
