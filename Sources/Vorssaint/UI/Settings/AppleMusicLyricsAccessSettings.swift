// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import MusicKit
import AppKit

/// Access is an app preference, not a login session. A successful macOS
/// authorization alone must not be presented as verified lyric retrieval.
struct AppleMusicLyricsAccessSettings: View {
    let strings: NotchAppleMusicLyricsStrings
    let music: NotchMusicExtrasStrings
    @AppStorage(DefaultsKey.notchLyricsAppleMusicConnected) private var enabled = false
    @ObservedObject private var provider = NotchAppleMusicLyricsProvider.shared
    @ObservedObject private var lyrics = NotchLyricsService.shared
    @State private var authorization = MusicAuthorization.currentStatus

    private var active: Bool { enabled && authorization == .authorized }
    private var permissionDenied: Bool { authorization == .denied || authorization == .restricted }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { status; Spacer(minLength: 12); accessButton }
                VStack(alignment: .leading, spacing: 8) { status; accessButton }
            }
            if permissionDenied {
                Text(strings.permissionHint).font(.caption).foregroundStyle(.secondary)
            } else if active, lyrics.usesAppleMusic, lyrics.importedName == nil {
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(strings.accountHint).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshPermission() }
        .onChange(of: enabled) { refreshPermission() }
        .onChange(of: provider.requestingAuthorization) { refreshPermission() }
    }

    @ViewBuilder private var status: some View {
        if provider.requestingAuthorization {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(strings.enabling) }
        } else if permissionDenied {
            Label(strings.permissionDenied, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        } else if active {
            Label(strings.accessActive, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label(strings.accessInactive, systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private var accessButton: some View {
        Button(active ? strings.disconnect : strings.connect) {
            if active { lyrics.disconnectAppleMusic() } else { lyrics.connectAppleMusic() }
        }.disabled(provider.requestingAuthorization)
    }

    private var detail: String? {
        switch lyrics.state {
        case .ready: return strings.verified
        case .loading: return music.loading
        case .appleMusicSubscription: return strings.subscription
        case .appleMusicDenied: return strings.denied
        case .appleMusicSignIn: return strings.refreshHint
        case .failed: return music.failed
        case .unavailable: return music.unavailable
        case .appleMusicOnly: return strings.only
        default: return nil
        }
    }

    private func refreshPermission() { authorization = MusicAuthorization.currentStatus }
}
