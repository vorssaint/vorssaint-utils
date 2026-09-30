// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelTimeZoneSwitcherView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = TimeZoneSwitchService.shared
    @State private var query = ""

    var onClose: () -> Void

    private var strings: TimeZoneSwitcherFeatureStrings { FeatureStrings.timeZoneSwitcher(l10n.language) }

    private var searchResults: [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return TimeZoneSwitchSupport.search(query, limit: 8).filter { !service.isFavorite($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            currentZoneCard
            searchField
            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(searchResults, id: \.self) { identifier in
                            searchRow(identifier)
                        }
                    }
                }
                .frame(maxHeight: 140)
            } else {
                favoritesList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.pageTitle, systemImage: "globe")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .timeZoneSwitcher
                appDelegate()?.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuSettings)
            .accessibilityLabel(l10n.s.menuSettings)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }

    private var currentZoneCard: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(strings.currentLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                Text(TimeZoneSwitchSupport.displayName(for: service.currentIdentifier))
                    .font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            if let offset = TimeZoneSwitchSupport.offsetLabel(for: service.currentIdentifier) {
                Text(offset)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .panelCard()
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(strings.searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
        }
        .padding(7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var favoritesList: some View {
        if service.favorites.isEmpty {
            VStack(spacing: 3) {
                Text(strings.emptyFavoritesTitle).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                Text(strings.emptyFavoritesHint).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .panelCard()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(service.favorites, id: \.self) { identifier in
                        favoriteRow(identifier)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func searchRow(_ identifier: String) -> some View {
        HStack(spacing: 8) {
            zoneLabel(identifier)
            Spacer(minLength: 4)
            Button {
                service.addFavorite(identifier)
                query = ""
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .help(strings.addFavoriteHelp)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    private func favoriteRow(_ identifier: String) -> some View {
        let isCurrent = identifier == service.currentIdentifier
        return HStack(spacing: 8) {
            zoneLabel(identifier)
            Spacer(minLength: 4)
            if isCurrent {
                Text(strings.currentBadge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            } else if service.switchingIdentifier == identifier {
                ProgressView().controlSize(.small)
            } else {
                Button(strings.switchButton) {
                    service.switchTimeZone(to: identifier)
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .disabled(service.state == .switching)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    private func zoneLabel(_ identifier: String) -> some View {
        HStack(spacing: 6) {
            Text(TimeZoneSwitchSupport.displayName(for: identifier))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            if let offset = TimeZoneSwitchSupport.offsetLabel(for: identifier) {
                Text(offset)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
    }
}
