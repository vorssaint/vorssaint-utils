// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// One-time update note for the Dock Preview beta. It is intentionally separate
/// from the first-run onboarding so clean installs keep their normal flow.
struct DockPreviewIntroView: View {
    var onDismiss: () -> Void
    var onEnable: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                header
                demo
                explanation
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 20)

            Divider()
            footer
        }
        .frame(width: 660, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            dockPreview.syncWithPreferences()
        }
        .onReceive(refreshTimer) { _ in
            dockPreview.syncWithPreferences()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(l10n.s.dockPreviewName)
                    .font(.system(size: 24, weight: .bold))
                PanelBetaBadge(text: l10n.s.betaBadge)
            }

            Text(l10n.s.dockPreviewEnableCaption)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
    }

    private var demo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            AnimatedBundleGIF(name: "dockPreview", subdirectory: "Gifs")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(10)
        }
        .frame(height: 246)
        .clipped()
    }

    private var explanation: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text(l10n.s.dockPreviewIntroPeek)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                Text(l10n.s.betaFeatureWarning)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if dockPreview.dockMagnification {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "dock.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(l10n.s.dockPreviewMagnificationBlocked)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            Text(l10n.s.dockPreviewIntroSettingsHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var footer: some View {
        HStack {
            Button(l10n.s.dockPreviewIntroLater) {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(dockPreview.dockMagnification
                   ? l10n.s.dockPreviewIntroMagnificationAction
                   : l10n.s.dockPreviewIntroEnable) {
                onEnable()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(dockPreview.dockMagnification)
            .help(dockPreview.dockMagnification ? l10n.s.dockPreviewIntroMagnificationAction : l10n.s.dockPreviewIntroEnable)
        }
        .padding(16)
    }
}

private struct AnimatedBundleGIF: NSViewRepresentable {
    let name: String
    let subdirectory: String

    func makeNSView(context: Context) -> NSImageView {
        let view = AnimatedImageView()
        view.imageAlignment = .alignCenter
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard view.image == nil else { return }
        if let url = Bundle.main.url(forResource: name,
                                     withExtension: "gif",
                                     subdirectory: subdirectory),
           let image = NSImage(contentsOf: url) {
            view.image = image
        } else {
            view.image = NSImage(systemSymbolName: "dock.rectangle",
                                 accessibilityDescription: nil)
        }
    }
}

private final class AnimatedImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
