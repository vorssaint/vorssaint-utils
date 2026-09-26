// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Full-screen overlay shown while the keyboard is locked for cleaning. It makes
/// the locked state unmistakable, shows live progress toward the unlock gesture,
/// and offers a mouse-clickable Unlock button so there is always an obvious way
/// out (the mouse is never locked).
struct CleaningOverlayView: View {
    @ObservedObject private var manager = CleaningModeManager.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.cleaningModeKeepScreenVisible) private var keepScreenVisible = false

    var body: some View {
        ZStack {
            if keepScreenVisible {
                Color.clear.ignoresSafeArea()
                compactCornerHUD
            } else {
                Color.black.ignoresSafeArea()
                fullBlackoutContent
            }
        }
    }

    private var fullBlackoutContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.white)

            Text(l10n.s.cleaningOverlayTitle)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)

            Text(l10n.s.cleaningOverlaySubtitle)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            fullProgressDots
                .padding(.top, 2)

            Button(action: { manager.deactivate() }) {
                Text(l10n.s.cleaningOverlayUnlock)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(minWidth: 130)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Text(l10n.s.cleaningOverlayMouseHint)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(44)
        .frame(maxWidth: 460)
    }

    private var compactCornerHUD: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.s.cleaningOverlayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    HStack(spacing: 8) {
                        Text(l10n.s.cleaningOverlaySubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)

                        compactProgressDots
                    }
                }

                Button(action: { manager.deactivate() }) {
                    Text(l10n.s.cleaningOverlayUnlock)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(HUDBackdrop(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 6)
            .padding(.top, 40)
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var fullProgressDots: some View {
        HStack(spacing: 11) {
            ForEach(0..<manager.unlockThreshold, id: \.self) { index in
                Circle()
                    .fill(index < manager.unlockProgress ? Color.white : Color.white.opacity(0.22))
                    .frame(width: 12, height: 12)
            }
        }
        .animation(.easeOut(duration: 0.15), value: manager.unlockProgress)
    }

    private var compactProgressDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<manager.unlockThreshold, id: \.self) { index in
                Circle()
                    .fill(index < manager.unlockProgress ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.15), value: manager.unlockProgress)
    }
}
