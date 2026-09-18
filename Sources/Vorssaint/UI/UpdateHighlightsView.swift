// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A static illustration of the new feature, following the layout editor preview.
struct UpdateHighlightsView: View {
    @ObservedObject private var l10n = L10n.shared
    let onFinish: () -> Void

    private var text: NotchTourStrings { FeatureStrings.notchTour(l10n.language) }
    private var artwork: NSImage? {
        Bundle.main.url(forResource: "highlights-notch", withExtension: "png", subdirectory: "Images")
            .flatMap(NSImage.init(contentsOf:))
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
                if let artwork {
                    Image(nsImage: artwork).resizable().scaledToFit()
                } else {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 72, weight: .light)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 500, height: 268)
            .accessibilityHidden(true)

            Text(text.caption)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 500, height: 58)

            HStack {
                Button(l10n.s.highlightsConfigure) {
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
        .frame(width: 600, height: 552)
    }
}
