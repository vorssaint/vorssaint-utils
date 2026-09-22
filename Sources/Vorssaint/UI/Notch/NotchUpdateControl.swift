// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The same offer and progress as the menu panel, kept inside the island's
/// existing header so it cannot displace or resize the active tool.
struct NotchUpdateControl: View {
    @ObservedObject private var updates = UpdateService.shared
    let action: () -> Void
    var compact = false
    @ObservedObject private var l10n = L10n.shared

    @ViewBuilder var body: some View {
        switch updates.state {
        case let .available(version):
            let tint: Color = UpdateServiceSupport.SemanticVersion(raw: version)?.isPrerelease == true ? .orange : .blue
            let title = "\(l10n.s.updateBannerTitle), \(l10n.s.versionPrefix) \(version)"
            Button(action: action) {
                Group {
                    if compact {
                        Image(systemName: "arrow.down.circle.fill")
                    } else {
                        Label(l10n.s.updateBannerAction, systemImage: "arrow.down.circle.fill")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(tint)
            .fixedSize()
            .help(title)
            .accessibilityLabel(title)
            .accessibilityHint(l10n.s.updateBannerAction)
        case let .downloading(progress):
            progressIndicator(title: l10n.s.updateDownloading, fraction: progress)
        case .installing:
            progressIndicator(title: l10n.s.updateInstalling)
        default:
            EmptyView()
        }
    }

    private func progressIndicator(title: String, fraction: Double? = nil) -> some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.small)
            if !compact {
                if let fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                } else {
                    Text(title).lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .font(.system(size: 10, weight: .medium))
        .frame(maxWidth: compact ? nil : 110)
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    }
}
