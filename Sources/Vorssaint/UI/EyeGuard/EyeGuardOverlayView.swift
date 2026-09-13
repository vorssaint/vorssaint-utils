// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The break screen. Black, with the time left and a Skip button that is always
/// there — a break nobody can leave is a Mac nobody can reach.
struct EyeGuardOverlayView: View {
    @ObservedObject private var service = EyeGuardService.shared
    @ObservedObject private var l10n = L10n.shared

    private var strings: EyeGuardStrings { FeatureStrings.eyeGuard(l10n.language) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "eye")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(.white)

                Text(strings.breakHeadline)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)

                if case .onBreak(let secondsLeft) = service.phase {
                    Text(strings.breakRemaining(secondsLeft: secondsLeft))
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }

                Button(action: { service.skipBreak() }) {
                    Text(strings.skipButton)
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
            }
        }
    }
}
