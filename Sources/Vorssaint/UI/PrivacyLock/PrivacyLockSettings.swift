// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Privacy Lock's page, in two tabs: the apps that sit behind a shield, and the
/// files and folders locked with a password of their own. Apps and items go in
/// by dropping them on the page, by right-clicking them in Finder, or from the
/// list of running apps.
struct PrivacyLockSettings: View {
    private enum Tab: Hashable { case apps, files }

    private struct RunningEntry: Identifiable {
        let id: String // bundle id
        let name: String
        let icon: NSImage
        let url: URL
    }

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var index = LockedItemIndex.shared
    @AppStorage(DefaultsKey.privacyLockEnabled) private var enabled = false
    @AppStorage(DefaultsKey.appLockEnabled) private var appLockEnabled = false
    @AppStorage(DefaultsKey.appLockedApps) private var storedApps = ""
    @AppStorage(DefaultsKey.appLockMethod) private var method = AppLockMethod.biometric.rawValue
    @AppStorage(DefaultsKey.appLockUseFace) private var useFace = true
    @AppStorage(DefaultsKey.appLockRelock) private var relock = AppLockRelock.fiveMinutes.rawValue
    @AppStorage(DefaultsKey.fileLockEnabled) private var fileLockEnabled = true
    @AppStorage(DefaultsKey.fileLockRemember) private var remember = false

    @State private var tab: Tab = .apps
    @State private var hasPassword = PrivacyLockKeychain.hasAppLockPassword
    @State private var quickActionsInstalled = PrivacyLockQuickActions.isInstalled
    @State private var running: [RunningEntry] = []
    @State private var search = ""
    @State private var appsTargeted = false
    @State private var filesTargeted = false
    @State private var message: String?

    private var text: PrivacyLockFeatureStrings { FeatureStrings.privacyLock(l10n.language) }
    private var lockedApps: [String] {
        PrivacyLockSupport.lockedBundleIDs(from: storedApps, ownBundleID: Bundle.main.bundleIdentifier)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Picker("", selection: $tab) {
                    Text(text.tabApps).tag(Tab.apps)
                    Text(text.tabFiles).tag(Tab.files)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!enabled)
                if tab == .apps { appsTab } else { filesTab }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .opacity(enabled ? 1 : 0.55)
        }
        .onAppear {
            hasPassword = PrivacyLockKeychain.hasAppLockPassword
            quickActionsInstalled = PrivacyLockQuickActions.isInstalled
            index.pruneMissing()
            refreshRunning()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshRunning() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(text.title).font(.title2.bold())
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle(text.title, isOn: Binding(get: { enabled }, set: { newValue in
                if newValue {
                    enabled = true
                    apply()
                    if fileLockEnabled && !PrivacyLockQuickActions.isInstalled { installQuickActions() }
                } else {
                    Task {
                        guard await AppLockService.authorize() else { return }
                        enabled = false
                        apply()
                    }
                }
            })).labelsHidden().toggleStyle(.switch).accessibilityLabel(text.title)
        }
    }

    private var summary: String {
        guard enabled else { return text.hint }
        return [String(format: text.appsCountFormat, lockedApps.count),
                String(format: text.itemsCountFormat, index.records.count)].joined(separator: " · ")
    }

    // MARK: - Apps tab

    private var appsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: text.appLockTitle) {
                Text(text.appLockHint).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsRow(symbol: "lock.shield", title: text.appLockToggle) {
                    Toggle(text.appLockToggle, isOn: Binding(get: { appLockEnabled }, set: { newValue in
                        if newValue { appLockEnabled = true; apply() }
                        else {
                            Task {
                                guard await AppLockService.authorize() else { return }
                                appLockEnabled = false
                                apply()
                            }
                        }
                    })).labelsHidden().toggleStyle(.switch)
                }
                SettingsChoiceRow(symbol: "touchid", title: text.methodTitle, selection: Binding(
                    get: { method },
                    set: { newValue in
                        Task {
                            guard await AppLockService.authorize() else { return }
                            if newValue == AppLockMethod.password.rawValue, !PrivacyLockKeychain.hasAppLockPassword {
                                guard setPassword() else { return }
                            }
                            method = newValue
                            apply()
                        }
                    })) {
                    Text(text.methodBiometric).tag(AppLockMethod.biometric.rawValue)
                    Text(text.methodPassword).tag(AppLockMethod.password.rawValue)
                }
                if method == AppLockMethod.password.rawValue {
                    SettingsRow(symbol: "key", title: hasPassword ? text.passwordSet : text.methodPassword) {
                        Button(hasPassword ? text.changePassword : text.setPassword) {
                            Task { if await AppLockService.authorize() { _ = setPassword() } }
                        }
                    }
                }
                if FaceUnlockSupport.isEnabled() && method == AppLockMethod.biometric.rawValue {
                    SettingsRow(symbol: "faceid", title: text.useFaceTitle, caption: text.useFaceCaption) {
                        Toggle(text.useFaceTitle, isOn: $useFace).labelsHidden().toggleStyle(.switch)
                    }
                }
                SettingsMenuRow(symbol: "clock.arrow.circlepath", title: text.relockTitle, selection: $relock) {
                    Text(text.relockEvery).tag(AppLockRelock.everyTime.rawValue)
                    Text(text.relock1).tag(AppLockRelock.oneMinute.rawValue)
                    Text(text.relock5).tag(AppLockRelock.fiveMinutes.rawValue)
                    Text(text.relock15).tag(AppLockRelock.fifteenMinutes.rawValue)
                    Text(text.relockQuit).tag(AppLockRelock.untilQuit.rawValue)
                }
            }

            SettingsCard(title: text.lockedAppsTitle) {
                if !lockedApps.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(lockedApps, id: \.self) { id in
                            lockedAppRow(id)
                            if id != lockedApps.last { Divider().padding(.leading, 40) }
                        }
                    }
                }
                DropZone(symbol: "square.and.arrow.down.on.square", title: text.dropAppsHint,
                         button: text.addApp, isTargeted: appsTargeted) { chooseApps() }
                    .onDrop(of: [.fileURL], isTargeted: $appsTargeted) { providers in
                        loadURLs(providers) { urls in AppLockService.shared.lock(appsAt: urls.filter { $0.pathExtension == "app" }); refreshRunning() }
                        return true
                    }
                Text(text.dockNote).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: text.runningAppsTitle) {
                TextField(text.searchPlaceholder, text: $search).textFieldStyle(.roundedBorder)
                VStack(spacing: 0) {
                    ForEach(filteredRunning) { entry in
                        HStack(spacing: 10) {
                            Image(nsImage: entry.icon).resizable().frame(width: 26, height: 26)
                            Text(entry.name).lineLimit(1)
                            Spacer(minLength: 8)
                            Toggle(entry.name, isOn: Binding(
                                get: { lockedApps.contains(entry.id) },
                                set: { newValue in
                                    if newValue { AppLockService.shared.lock(appsAt: [entry.url]) }
                                    else { Task { await AppLockService.shared.removeLock(forBundleIDs: [entry.id]) } }
                                })).labelsHidden().toggleStyle(.switch)
                        }
                        .padding(.vertical, 6)
                        if entry.id != filteredRunning.last?.id { Divider().padding(.leading, 36) }
                    }
                }
            }
            Text(text.appLockCaveat).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lockedAppRow(_ id: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        return HStack(spacing: 10) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()).resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(appName(for: id, url: url)).lineLimit(1)
                Text(text.lockedBadge).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                Task { await AppLockService.shared.removeLock(forBundleIDs: [id]) }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(text.removeApp)
            .accessibilityLabel(text.removeApp)
        }
        .padding(.vertical, 6)
    }

    private var filteredRunning: [RunningEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? running : running.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Files tab

    private var filesTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: text.fileLockTitle) {
                Text(text.fileLockHint).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DropZone(symbol: "doc.badge.plus", title: text.dropFilesHint,
                         button: text.chooseFiles, isTargeted: filesTargeted) { chooseFiles() }
                    .onDrop(of: [.fileURL], isTargeted: $filesTargeted) { providers in
                        loadURLs(providers) { urls in FileLockController.shared.lock(urls) }
                        return true
                    }
            }

            SettingsCard(title: text.lockedItemsTitle) {
                if index.records.isEmpty {
                    Text(text.noItems).font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(index.records) { record in
                            lockedItemRow(record)
                            if record.id != index.records.last?.id { Divider().padding(.leading, 40) }
                        }
                    }
                }
            }

            SettingsCard(title: text.quickActionsTitle) {
                SettingsRow(symbol: quickActionsInstalled ? "checkmark.circle.fill" : "contextualmenu.and.cursorarrow",
                            title: quickActionsInstalled ? text.quickInstalled : text.quickActionsTitle,
                            caption: text.quickActionsHint) {
                    if quickActionsInstalled {
                        Button(text.quickRemove) {
                            PrivacyLockQuickActions.remove()
                            quickActionsInstalled = false
                        }
                    } else {
                        Button(text.quickInstall) { installQuickActions() }
                    }
                }
                Text(text.quickNote).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard {
                SettingsRow(symbol: "doc.badge.ellipsis", title: text.fileLockToggle) {
                    Toggle(text.fileLockToggle, isOn: $fileLockEnabled).labelsHidden().toggleStyle(.switch)
                        .onChange(of: fileLockEnabled) { _, _ in apply() }
                }
                SettingsRow(symbol: "touchid", title: text.rememberTitle, caption: text.rememberCaption) {
                    Toggle(text.rememberTitle, isOn: $remember).labelsHidden().toggleStyle(.switch)
                }
            }
            Text(text.fileCaveat).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lockedItemRow(_ record: LockedItemIndex.Record) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: record.exists ? record.path : "/"))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.originalName).lineLimit(1)
                Text(record.exists ? record.lockedAt.formatted(date: .abbreviated, time: .shortened) : text.missing)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if record.remembered {
                Image(systemName: "touchid").foregroundStyle(.secondary).help(text.rememberTitle)
            }
            Button(text.reveal) { NSWorkspace.shared.activateFileViewerSelecting([record.url]) }
                .disabled(!record.exists)
            Button(text.unlock) { FileLockController.shared.unlock([record.url]) }
                .disabled(!record.exists)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func apply() {
        AppLockService.shared.syncWithPreferences()
        FileLockController.shared.syncWithPreferences()
        hasPassword = PrivacyLockKeychain.hasAppLockPassword
        refreshRunning()
    }

    private func installQuickActions() {
        quickActionsInstalled = PrivacyLockQuickActions.install(language: l10n.language)
    }

    private func setPassword() -> Bool {
        guard let password = PrivacyLockPrompts.askAppLockPassword() else { return false }
        do {
            try PrivacyLockKeychain.setAppLockPassword(password)
            hasPassword = true
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        AppLockService.shared.lock(appsAt: panel.urls)
        refreshRunning()
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        FileLockController.shared.lock(panel.urls)
    }

    private func loadURLs(_ providers: [NSItemProvider], then done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }

    private func refreshRunning() {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        running = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  PrivacyLockSupport.canLock(bundleID: id, ownBundleID: own),
                  let url = app.bundleURL, seen.insert(id).inserted else { return nil }
            return RunningEntry(id: id, name: app.localizedName ?? id,
                                icon: app.icon ?? NSWorkspace.shared.icon(forFile: url.path), url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appName(for bundleID: String, url: URL?) -> String {
        guard let url else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// A dashed target for dropping things on, with a button for choosing them instead.
private struct DropZone: View {
    let symbol: String
    let title: String
    let button: String
    let isTargeted: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text(title).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button, action: action)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(isTargeted ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}
