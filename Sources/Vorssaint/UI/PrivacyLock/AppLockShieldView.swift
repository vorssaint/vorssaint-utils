// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The screen laid over a locked app, on every display.
struct AppLockShieldView: View {
    @ObservedObject var state: AppLockShieldState
    @ObservedObject private var l10n = L10n.shared
    let unlockWithTouchID: () -> Void
    let unlockWithPassword: (String) -> Void
    let dismiss: () -> Void
    @State private var password = ""
    @FocusState private var focused: Bool

    private var text: PrivacyLockFeatureStrings { FeatureStrings.privacyLock(l10n.language) }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            Color.black.opacity(0.35)
            VStack(spacing: 14) {
                if let icon = state.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 72, height: 72)
                }
                Text(String(format: text.shieldTitleFormat, state.appName))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                if state.method == .password {
                    HStack(spacing: 8) {
                        SecureField(text.shieldPasswordPlaceholder, text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .focused($focused)
                            .onSubmit(submit)
                        Button(text.shieldUnlock, action: submit)
                            .buttonStyle(.borderedProminent)
                            .disabled(password.isEmpty || state.isAuthenticating)
                    }
                    .onAppear { focused = true }
                } else {
                    Button(action: unlockWithTouchID) {
                        Label(text.shieldTouchID, systemImage: "touchid")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isAuthenticating)
                    .opacity(state.isAuthenticating ? 0.5 : 1)
                }

                Button(text.shieldNotNow, action: dismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .keyboardShortcut(.cancelAction)

                if state.isScanningFace {
                    Label(text.shieldFaceLooking, systemImage: "faceid")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .symbolEffect(.pulse, options: .repeating)
                }
                if let message = state.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    private func submit() {
        let entered = password
        password = ""
        unlockWithPassword(entered)
    }
}
