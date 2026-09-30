// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct TimeZoneSwitcherView: View {
    @ObservedObject private var service = TimeZoneSwitchService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var query = ""
    @AppStorage(DefaultsKey.timeZoneSwitcherCommandBarEnabled) private var commandBarEnabled = true

    private var strings: TimeZoneSwitcherFeatureStrings { FeatureStrings.timeZoneSwitcher(l10n.language) }

    private var searchResults: [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return TimeZoneSwitchSupport.search(query).filter { !service.isFavorite($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.pageTitle).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)

            currentZoneCard
                .padding(.horizontal, 14).padding(.bottom, 10)

            Text(strings.automaticHint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(strings.searchPlaceholder, text: $query).textFieldStyle(.plain)
            }
            .padding(9).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 14).padding(.bottom, 8)

            if !searchResults.isEmpty {
                List(searchResults, id: \.self) { identifier in
                    searchRow(identifier)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
                .frame(maxHeight: 220)
                Divider()
            }

            List {
                Section(strings.favoritesHeader) {
                    if service.favorites.isEmpty {
                        emptyFavorites
                    } else {
                        ForEach(service.favorites, id: \.self) { identifier in
                            favoriteRow(identifier)
                        }
                        .onMove { service.moveFavorites(fromOffsets: $0, toOffset: $1) }
                    }
                }
                Section {
                    Toggle(strings.commandBarToggle, isOn: $commandBarEnabled)
                    Text(strings.commandBarCaption)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(strings.switchFailedTitle,
               isPresented: Binding(get: { service.state == .failed },
                                    set: { if !$0 { service.dismissFailure() } })) {
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
        } message: {
            Text(strings.switchFailedMessage)
        }
    }

    private var currentZoneCard: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(strings.currentLabel).font(.caption).foregroundStyle(.secondary)
                Text(TimeZoneSwitchSupport.displayName(for: service.currentIdentifier))
                    .font(.system(size: 14, weight: .semibold))
                let region = TimeZoneSwitchSupport.regionName(for: service.currentIdentifier)
                Text(region.isEmpty ? service.currentIdentifier : region)
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if let offset = TimeZoneSwitchSupport.offsetLabel(for: service.currentIdentifier) {
                Text(offset)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyFavorites: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strings.emptyFavoritesTitle).font(.callout).foregroundStyle(.secondary)
            Text(strings.emptyFavoritesHint).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
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
        .padding(.vertical, 3)
    }

    private func favoriteRow(_ identifier: String) -> some View {
        let isCurrent = identifier == service.currentIdentifier
        return HStack(spacing: 8) {
            zoneLabel(identifier)
            Spacer(minLength: 4)
            if isCurrent {
                Text(strings.currentBadge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            } else if service.switchingIdentifier == identifier {
                ProgressView().controlSize(.small)
            } else {
                Button(strings.switchButton) {
                    service.switchTimeZone(to: identifier)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(service.state == .switching)
            }
            Button {
                service.removeFavorite(identifier)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(strings.removeFavoriteHelp)
        }
        .padding(.vertical, 3)
    }

    private func zoneLabel(_ identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(TimeZoneSwitchSupport.displayName(for: identifier))
                    .font(.system(size: 12, weight: .semibold))
                if let offset = TimeZoneSwitchSupport.offsetLabel(for: identifier) {
                    Text(offset)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            let region = TimeZoneSwitchSupport.regionName(for: identifier)
            if !region.isEmpty {
                Text(region)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}
