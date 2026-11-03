// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

struct AppPickerView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var apps: [InstalledApps.InstalledApp] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var isBrowsingApplications = false
    @State private var sortOrder = AppListSort.name
    @State private var usageCancellation = CleanerSupport.ScanCancellation()
    /// Whether the picker is on screen, so a list that finishes loading after
    /// it was closed does not start measuring for nobody.
    @State private var isOnScreen = false

    var compact = false
    var canBrowseApplications = false
    /// Whether a program that is not packaged as an app may be chosen too.
    /// Only the lists that can recognize one at runtime ask for this: offering
    /// it anywhere else would take an entry that never matches anything
    /// (issue #1009).
    var acceptsExecutables = false
    /// What a list that leaves some apps out says when nothing shows, so a
    /// missing app reads as a rule rather than a fault.
    var emptyNote: String? = nil
    /// Shows each app's size and, on hover, when it was last opened. Measuring
    /// reads every bundle, so only the uninstaller asks for it.
    var showsUsage = false
    var loadApps: () -> [InstalledApps.InstalledApp] = { InstalledApps.installedApplications() }
    var onCancel: () -> Void
    var onSelect: (URL) -> Void
    var onSelectApp: ((InstalledApps.InstalledApp) -> Void)? = nil

    init(compact: Bool = false,
         canBrowseApplications: Bool = false,
         acceptsExecutables: Bool = false,
         emptyNote: String? = nil,
         showsUsage: Bool = false,
         onCancel: @escaping () -> Void,
         onSelect: @escaping (URL) -> Void,
         onSelectApp: ((InstalledApps.InstalledApp) -> Void)? = nil,
         loadApps: @escaping () -> [InstalledApps.InstalledApp] = { InstalledApps.installedApplications() }) {
        self.compact = compact
        self.canBrowseApplications = canBrowseApplications
        self.acceptsExecutables = acceptsExecutables
        self.emptyNote = emptyNote
        self.showsUsage = showsUsage
        self.onCancel = onCancel
        self.onSelect = onSelect
        self.onSelectApp = onSelectApp
        self.loadApps = loadApps
    }

    private var filteredApps: [InstalledApps.InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = showsUsage ? AppListSort.sorted(apps, by: sortOrder) : apps
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { app in
            app.name.localizedCaseInsensitiveContains(trimmed)
                || (app.bundleID?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (app.identity?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            header
            TextField(l10n.s.uninstallerPickerSearch, text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: compact ? 11 : 13))
            if showsUsage {
                Picker("", selection: $sortOrder) {
                    Text(l10n.s.uninstallerSortName).tag(AppListSort.name)
                    Text(l10n.s.uninstallerSortSize).tag(AppListSort.size)
                    Text(l10n.s.uninstallerSortLastUsed).tag(AppListSort.lastUsed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(compact ? .small : .regular)
            }
            appList
        }
        .padding(compact ? 10 : 18)
        .frame(width: compact ? nil : 520, height: compact ? nil : 560)
        .onAppear {
            isOnScreen = true
            loadAppsIfNeeded()
        }
        .onDisappear {
            isOnScreen = false
            usageCancellation.cancel()
        }
        .fileImporter(isPresented: $isBrowsingApplications,
                      allowedContentTypes: acceptsExecutables
                          ? [.applicationBundle, .executable, .unixExecutable]
                          : [.applicationBundle]) { result in
            guard let url = try? result.get() else { return }
            onSelect(url)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l10n.s.uninstallerPickerTitle)
                .font(.system(size: compact ? 12 : 16, weight: .semibold))
            Spacer()
            if canBrowseApplications {
                Button {
                    isBrowsingApplications = true
                } label: {
                    Label(l10n.s.uninstallerChoose, systemImage: "folder")
                }
                .controlSize(compact ? .small : .regular)
            }
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
                if let emptyNote {
                    Text(emptyNote)
                        .font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, compact ? 6 : 24)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 150 : 360)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(apps) { app in
                        Button {
                            if let onSelectApp {
                                onSelectApp(app)
                            } else {
                                onSelect(app.url)
                            }
                        } label: {
                            AppPickerRow(app: app, compact: compact, showsUsage: showsUsage)
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
        guard !isLoading else { return }
        if !apps.isEmpty {
            // Coming back to a list whose measuring was stopped: finish it.
            let unmeasured = apps.filter { $0.size == nil }
            if showsUsage, !unmeasured.isEmpty { measureUsage(of: unmeasured) }
            return
        }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = loadApps()
            DispatchQueue.main.async {
                apps = loaded
                isLoading = false
                if showsUsage, isOnScreen { measureUsage(of: loaded) }
            }
        }
    }

    /// Fills in sizes and last-used dates after the list is already on screen,
    /// a few apps at a time, so a big Applications folder never holds it up.
    private func measureUsage(of loaded: [InstalledApps.InstalledApp]) {
        usageCancellation.cancel()
        usageCancellation = CleanerSupport.ScanCancellation()
        let cancellation = usageCancellation
        DispatchQueue.global(qos: .utility).async {
            var batch: [String: (size: Int64, lastUsed: Date?)] = [:]
            func publish() {
                let chunk = batch
                batch = [:]
                DispatchQueue.main.async {
                    for index in apps.indices {
                        guard let usage = chunk[apps[index].id] else { continue }
                        apps[index].size = usage.size
                        apps[index].lastUsed = usage.lastUsed
                    }
                }
            }
            for app in loaded {
                if cancellation.isCancelled { return }
                batch[app.id] = InstalledApps.usage(of: app.url)
                if batch.count >= 8 { publish() }
            }
            publish()
        }
    }
}

private struct AppPickerRow: View {
    @ObservedObject private var l10n = L10n.shared
    let app: InstalledApps.InstalledApp
    var compact: Bool
    var showsUsage = false

    private var lastUsedHelp: String {
        guard showsUsage, app.size != nil else { return "" }
        guard let lastUsed = app.lastUsed else { return l10n.s.uninstallerNeverUsed }
        return String(format: l10n.s.uninstallerLastUsedFormat,
                      lastUsed.formatted(date: .abbreviated, time: .shortened))
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: compact ? 20 : 28, height: compact ? 20 : 28)
            VStack(alignment: .leading, spacing: 1) {
                let location = app.identity.flatMap(InstalledApps.location(for:))
                Text(app.name)
                    .font(.system(size: compact ? 11 : 13, weight: .medium))
                    .lineLimit(1)
                Text(location ?? app.bundleID ?? app.url.path)
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(location == nil ? .middle : .head)
            }
            Spacer(minLength: 0)
            if showsUsage {
                if let size = app.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.system(size: compact ? 10 : 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 5 : 7)
        .help(lastUsedHelp)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.001))
        }
    }
}

/// How the uninstaller's app list is ordered. Size puts the biggest first;
/// last used puts the apps opened longest ago (or never) first, so the ones
/// nobody needs are at the top. Apps still being measured always sit last.
enum AppListSort: Hashable {
    case name, size, lastUsed

    /// Ties always fall back to the name, so rows never swap places at random.
    private static func byName(_ lhs: InstalledApps.InstalledApp, _ rhs: InstalledApps.InstalledApp) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    static func sorted(_ apps: [InstalledApps.InstalledApp], by order: AppListSort) -> [InstalledApps.InstalledApp] {
        switch order {
        case .name:
            return apps
        case .size:
            return apps.sorted { lhs, rhs in
                let (a, b) = (lhs.size ?? -1, rhs.size ?? -1)
                return a != b ? a > b : byName(lhs, rhs)
            }
        case .lastUsed:
            return apps.sorted { lhs, rhs in
                switch (lhs.size, rhs.size) {
                case (nil, nil): return byName(lhs, rhs)
                case (nil, _): return false
                case (_, nil): return true
                default:
                    let (a, b) = (lhs.lastUsed ?? .distantPast, rhs.lastUsed ?? .distantPast)
                    return a != b ? a < b : byName(lhs, rhs)
                }
            }
        }
    }
}
