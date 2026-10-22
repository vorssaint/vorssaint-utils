// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A fixed-size update inbox in the island's header. An offer adds a badge;
/// checking, downloading and installing keep their progress in the same slot.
struct NotchUpdateControl: View {
    @ObservedObject private var updates = UpdateService.shared
    let action: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var hasOffer: Bool {
        if case .available = updates.state { return true }
        return false
    }

    private var busy: Bool {
        switch updates.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var title: String {
        switch updates.state {
        case let .available(version):
            return "\(l10n.s.updateBannerTitle), \(l10n.s.versionPrefix) \(version)"
        case .downloading: return l10n.s.updateDownloading
        case .installing: return l10n.s.updateInstalling
        default: return l10n.s.updatesSection
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(hasOffer ? 0.9 : 0.55))
                .frame(width: 28, height: 28)
                .overlay(alignment: .topTrailing) {
                    if hasOffer {
                        Circle()
                            .fill(.blue)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(.black, lineWidth: 1))
                            .padding(3)
                            .accessibilityHidden(true)
                    } else if busy {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                            .frame(width: 10, height: 10)
                            .padding(1)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .disabled(busy)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(progressValue)
        .accessibilityIdentifier("notch.updates")
    }

    private var progressValue: String {
        if case let .downloading(progress?) = updates.state {
            return progress.formatted(.percent.precision(.fractionLength(0)))
        }
        return ""
    }
}
