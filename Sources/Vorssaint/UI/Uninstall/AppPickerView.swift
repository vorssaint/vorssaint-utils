// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AppPickerView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var apps: [InstalledApps.InstalledApp] = []
    @State private var query = ""
    @State private var isLoading = false

    var compact = false
    var loadApps: () -> [InstalledApps.InstalledApp] = { InstalledApps.installedApplications() }
    var onCancel: () -> Void
    var onSelect: (URL) -> Void

    init(compact: Bool = false,
         onCancel: @escaping () -> Void,
         onSelect: @escaping (URL) -> Void,
         loadApps: @escaping () -> [InstalledApps.InstalledApp] = { InstalledApps.installedApplications() }) {
        self.compact = compact
        self.onCancel = onCancel
        self.onSelect = onSelect
        self.loadApps = loadApps
    }

    private var filteredApps: [InstalledApps.InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(trimmed)
                || (app.bundleID?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            header
            TextField(l10n.s.uninstallerPickerSearch, text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: compact ? 11 : 13))
            appList
        }
        .padding(compact ? 10 : 18)
        .frame(width: compact ? nil : 520, height: compact ? nil : 560)
        .onAppear { loadAppsIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l10n.s.uninstallerPickerTitle)
                .font(.system(size: compact ? 12 : 16, weight: .semibold))
            Spacer()
            Button(l10n.s.uninstallerCancel, action: onCancel)
                .controlSize(compact ? .small : .regular)
        }
    }

    @ViewBuilder
    private var appList: some View {
        let apps = filteredApps
        if isLoading {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(compact ? .small : .regular)
                Text(l10n.s.uninstallerScanning)
                    .font(.system(size: compact ? 11 : 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 150 : 360)
        } else if apps.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "app.dashed")
                    .font(.system(size: compact ? 24 : 34, weight: .light))
                    .foregroundStyle(.secondary)
                Text(l10n.s.uninstallerPickerEmpty)
                    .font(.system(size: compact ? 11 : 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 150 : 360)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(apps) { app in
                        Button {
                            onSelect(app.url)
                        } label: {
                            AppPickerRow(app: app, compact: compact)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 3)
            }
            .frame(height: compact ? 235 : nil)
        }
    }

    private func loadAppsIfNeeded() {
        guard apps.isEmpty, !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = loadApps()
            DispatchQueue.main.async {
                apps = loaded
                isLoading = false
            }
        }
    }
}

private struct AppPickerRow: View {
    let app: InstalledApps.InstalledApp
    var compact: Bool

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: compact ? 20 : 28, height: compact ? 20 : 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: compact ? 11 : 13, weight: .medium))
                    .lineLimit(1)
                Text(app.bundleID ?? app.url.path)
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 5 : 7)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.001))
        }
    }
}
