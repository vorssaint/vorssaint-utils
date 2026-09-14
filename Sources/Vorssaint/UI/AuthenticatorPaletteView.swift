// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The code palette: a search field, the accounts with live codes and a
/// footer. Selection is driven by the service so the key monitor and the
/// mouse agree on one source of truth.
struct AuthenticatorPaletteView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var palette = AuthenticatorPaletteService.shared
    @ObservedObject private var service = AuthenticatorService.shared
    @FocusState private var searchFocused: Bool

    private var text: AuthenticatorFeatureStrings {
        FeatureStrings.authenticator(l10n.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 440)
        .background(HUDBackdrop(cornerRadius: 22, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: palette.presentationID) { _, _ in
            searchFocused = true
        }
        .onChange(of: palette.query) { _, _ in
            palette.refreshPanelLayout()
        }
        .onChange(of: service.accounts) { _, _ in
            palette.refreshPanelLayout()
        }
        .onAppear {
            searchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(text.searchPlaceholder, text: $palette.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !palette.query.isEmpty {
                Button {
                    palette.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Button {
                palette.scan()
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(text.scanScreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var content: some View {
        if service.accounts.isEmpty {
            emptyState
        } else if service.isLocked {
            lockedState
        } else if palette.rows.isEmpty {
            Text(text.noResults)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text.emptyPalette)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(text.scanScreen) { palette.scan() }
                Button(text.manageButton) { openSettings() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var lockedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text.requiresUnlock)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button(text.unlockButton) { palette.unlock() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(palette.rows) { account in
                        row(account)
                            .id(account.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
            .onChange(of: palette.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func row(_ account: OTPAccount) -> some View {
        let selected = palette.selectedID == account.id
        let peeking = palette.peekingID == account.id
        return Button {
            palette.use(account.id, typing: palette.returnTypes)
        } label: {
            HStack(spacing: 10) {
                AuthenticatorInitials(name: account.displayName)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if account.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if !account.secondaryName.isEmpty {
                        Text(account.secondaryName)
                            .font(.caption)
                            .foregroundStyle(selected ? .secondary : .tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                AuthenticatorCodeBadge(account: account, showsNext: peeking)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { palette.select(account.id) }
        }
        .contextMenu {
            Button(text.copyAction) { palette.use(account.id, typing: false) }
            Button(text.typeAction) { palette.use(account.id, typing: true) }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(text.footerHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(text.manageButton) { openSettings() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func openSettings() {
        palette.hide()
        service.openSettings()
    }
}

/// The issuer's first letters in a tinted circle, a stable colour per name
/// so a list reads at a glance without brand icons.
struct AuthenticatorInitials: View {
    let name: String

    var body: some View {
        Text(initials)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(color))
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        if letters.isEmpty { return "?" }
        return letters.joined()
    }

    private var color: Color {
        // Not `hashValue`: that is seeded per launch and the colour would drift.
        let sum = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        let hue = Double(sum % 360) / 360
        return Color(hue: hue, saturation: 0.45, brightness: 0.62)
    }
}

/// The live code with its countdown ring (or the counter for HOTP). This
/// is the only view subscribed to the clock, so a tick redraws the codes
/// and leaves the rest of the page alone.
struct AuthenticatorCodeBadge: View {
    let account: OTPAccount
    var showsNext = false
    /// A swept ring redraws its path every frame, which is worth it for the
    /// handful of rows in the palette and not for a long settings list.
    var animatesRing = true
    @ObservedObject private var service = AuthenticatorService.shared
    @ObservedObject private var clock = AuthenticatorClock.shared

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(codeText)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(showsNext ? Color.accentColor : .primary)
                    .monospacedDigit()
                if let upcomingText {
                    Text(upcomingText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            if account.kind == .hotp {
                Image(systemName: "number")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            } else {
                ring
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var codeText: String {
        let code = showsNext
            ? service.nextCode(for: account.id, at: clock.now)
            : service.code(for: account.id, at: clock.now)
        guard let code else {
            return service.isLocked ? FeatureStrings.authenticator(L10n.shared.language).lockedCode : "· · ·"
        }
        return OneTimePassword.grouped(code)
    }

    /// The upcoming code, shown small in the last seconds so a form that is
    /// still loading can be given the code that will be valid when it lands.
    private var upcomingText: String? {
        guard !showsNext, account.kind != .hotp,
              service.secondsRemaining(for: account, at: clock.now) <= 5,
              let next = service.nextCode(for: account.id, at: clock.now)
        else { return nil }
        return FeatureStrings.authenticator(L10n.shared.language).nextLabel + " " + OneTimePassword.grouped(next)
    }

    private var accessibilityText: String {
        let strings = FeatureStrings.authenticator(L10n.shared.language)
        let code = showsNext
            ? service.nextCode(for: account.id, at: clock.now)
            : service.code(for: account.id, at: clock.now)
        guard let code else {
            return service.isLocked ? strings.lockedCode : strings.secretUnavailable
        }
        if account.kind == .hotp { return code }
        return code + ", " + String(service.secondsRemaining(for: account, at: clock.now)) + " s"
    }

    private var ring: some View {
        let remaining = service.secondsRemaining(for: account, at: clock.now)
        let period = Double(max(account.period, 1))
        let fraction = Double(remaining) / period
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(remaining <= 5 ? Color.red : Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animatesRing ? .linear(duration: 1) : nil, value: remaining)
        }
        .frame(width: 18, height: 18)
    }
}
