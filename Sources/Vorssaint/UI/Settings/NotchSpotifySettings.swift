// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Connects the Spotify account behind the music page's heart. Until it is
/// connected, the row walks through registering a Spotify app step by step.
struct NotchSpotifySettings: View {
    @ObservedObject private var spotify = NotchSpotifyService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchSpotifyClientID) private var clientID = ""
    @State private var copied = false

    private static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    private var text: NotchSpotifyStrings { FeatureStrings.notchSpotify(l10n.language) }
    private var trimmedID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validID: Bool { NotchSpotifySupport.validClientID(trimmedID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if spotify.connection != .connected { setup.padding(.leading, settingsRowTextInset) }
        }
        .animation(.smooth(duration: 0.25), value: spotify.connection)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(text.account)
                Text(text.accountHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if spotify.connection == .connected {
                Label(text.connected, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .labelStyle(.titleAndIcon)
                Button(text.disconnect) { spotify.disconnect() }
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.getStarted.uppercased())
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            step(1, text.step1, done: false) {
                Link(destination: Self.dashboardURL) {
                    Label(text.openDeveloper, systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Self.dashboardURL.absoluteString)
            }
            step(2, text.step2, done: false) { redirectField }
            step(3, text.step3, done: validID) { clientIDField }
            Divider()
            footer
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
    }

    private func step<Accessory: View>(_ number: Int, _ title: String, done: Bool,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.accentColor : Color.secondary.opacity(0.18))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption2.weight(.semibold)).monospacedDigit()
                }
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.callout).fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var redirectField: some View {
        HStack(spacing: 0) {
            Text(NotchSpotifySupport.redirectURI)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.horizontal, 9)
            Divider().frame(height: 18)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(NotchSpotifySupport.redirectURI, forType: .string)
                copied = true
            } label: {
                Label(copied ? text.copied : text.copyRedirect, systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(copied ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(copied ? text.copied : text.copyRedirect)
        }
        .frame(height: 26)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.quaternary))
        .fixedSize()
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copied = false }
        }
    }

    private var clientIDField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(text.clientIDPlaceholder, text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: 300)
                    .disabled(spotify.connection == .connecting)
                    .onSubmit { if validID { spotify.connect() } }
                if validID {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.2), value: validID)
            if !trimmedID.isEmpty, !validID {
                Text(text.invalidClientID).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if spotify.connection == .failed {
                Label(text.connectFailed, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 12) {
                Text(text.premiumNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if spotify.connection == .connecting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(text.connecting).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button { spotify.connect() } label: {
                        Label(text.connect, systemImage: "link").padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!validID)
                }
            }
        }
    }
}
