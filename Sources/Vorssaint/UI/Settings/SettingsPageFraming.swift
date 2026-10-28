// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shared content bounds for ordinary Settings pages.
enum SettingsPageLayout {
    static let contentWidth: CGFloat = 760
    static let margin: CGFloat = 22
}

/// A compact introduction for a feature, inside a SettingsCard or Form section.
struct SettingsFeatureIntroduction: View {
    let title: String
    let symbol: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// Context for shared pages that do not describe a single feature.
struct SettingsPageDescription: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// Apply inside a scroll view; forms use `settingsFormFrame` instead.
    func settingsPageFrame() -> some View {
        frame(maxWidth: SettingsPageLayout.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(SettingsPageLayout.margin)
    }

    /// A form owns its scrolling viewport. Inset only its content, leaving the
    /// scroll indicators and native scroll-edge effects at the pane's edges.
    func settingsFormFrame() -> some View {
        GeometryReader { geometry in
            self
                .contentMargins(.horizontal,
                    max(SettingsPageLayout.margin,
                        (geometry.size.width - SettingsPageLayout.contentWidth) / 2),
                    for: .scrollContent)
                .contentMargins(.vertical, SettingsPageLayout.margin, for: .scrollContent)
        }
    }

    /// The shared column without the outer margin, for a pinned strip that
    /// already draws its own horizontal padding.
    func settingsPageWidth() -> some View {
        frame(maxWidth: SettingsPageLayout.contentWidth)
            .frame(maxWidth: .infinity)
    }
}
