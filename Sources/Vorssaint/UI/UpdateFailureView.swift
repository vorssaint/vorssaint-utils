// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shares the existing panel's measured banner slot; Details leads to About.
struct UpdateFailureBanner: View {
    let text: UpdateFailureStrings
    let currentVersion: String
    let isBusy: Bool
    let onRetry: () -> Void
    let onDetails: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(text.title).font(.system(size: 12, weight: .semibold))
                    Text(String(format: text.currentVersionFormat, currentVersion))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(text.dismiss)
                .accessibilityLabel(text.dismiss)
            }
            HStack(spacing: 8) {
                Button(text.retry, action: onRetry).disabled(isBusy)
                Button(text.details, action: onDetails)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The saved result remains here even after its menu-panel banner is dismissed.
struct UpdateFailureDetails: View {
    let failure: UpdateInstallFailure
    let text: UpdateFailureStrings
    let currentVersion: String
    let isBusy: Bool
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(text.title)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: text.currentVersionFormat, currentVersion))
                if let version = failure.attemptedVersion {
                    Text(String(format: text.attemptedVersionFormat, version))
                }
                Text(text.explanation(for: failure.code))
            }
            .font(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(text.retry, action: onRetry).disabled(isBusy)
                Button(text.downloadManually, action: onDownload)
            }
            Button(text.copyDetails, action: onCopy)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
