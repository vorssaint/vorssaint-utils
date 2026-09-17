// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct CommandBarAppShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.commandBarRowShortcuts) private var shortcutsRaw = ""
    @AppStorage(DefaultsKey.commandBarAliases) private var aliasesRaw = ""
    @AppStorage(DefaultsKey.commandBarPins) private var pinsRaw = ""
    @State private var query = ""
    @State private var filter = AppFilter.all
    @State private var message: String?

    private enum AppFilter { case all, pinned, shortcuts }
    private var text: CommandBarFeatureStrings { FeatureStrings.commandBar(l10n.language) }

    var body: some View {
        let shortcuts = CommandBarRowShortcuts.decode(shortcutsRaw)
        let aliases = CommandBarPreferences.decodeAliases(aliasesRaw)
        let pins = Set(CommandBarPreferences.decodePins(pinsRaw))
        let apps = visibleApps(shortcuts: shortcuts, aliases: aliases, pins: pins)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text.appCenterTitle)
                    .font(.title2.weight(.semibold))
                Text(text.appCenterCaption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(l10n.s.uninstallerPickerSearch, text: $query)
                        .textFieldStyle(.plain)
                        .accessibilityLabel(l10n.s.uninstallerPickerSearch)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(text.removeButton)
                    }
                }
                .padding(7)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                Picker(text.sourceApps, selection: $filter) {
                    Text(text.categoryAll).tag(AppFilter.all)
                    Text(text.pinnedTitle).tag(AppFilter.pinned)
                    Text(text.appShortcutsFilter).tag(AppFilter.shortcuts)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            Table(apps) {
                TableColumn(text.sourceApps) { entry in
                    HStack(spacing: 8) {
                        if let path = entry.revealPath {
                            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                                .resizable()
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                        }
                        Text(entry.title)
                            .lineLimit(1)
                            .help(entry.title)
                    }
                    .padding(.vertical, 4)
                }
                .width(min: 150, ideal: 210)

                TableColumn(text.appAliasLabel) { entry in
                    CommandBarAppAliasField(entry: entry, savedAlias: aliases[entry.stableKey] ?? "",
                                            text: text) { report($0, for: entry) }
                }
                .width(min: 110, ideal: 150)

                TableColumn(text.appShortcutLabel) { entry in
                    shortcutField(for: entry, shortcut: shortcuts[entry.stableKey])
                }
                .width(180)

                TableColumn(text.pinnedTitle) { entry in
                    let pinned = pins.contains(entry.stableKey)
                    Button {
                        service.togglePin(entry)
                    } label: {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                            .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .help(pinned ? text.actionUnpin : text.actionPin)
                    .accessibilityLabel("\(entry.title): \(pinned ? text.actionUnpin : text.actionPin)")
                }
                .width(min: 60, ideal: 80)
            }
            .tableStyle(.inset)
            .overlay {
                if apps.isEmpty {
                    VStack(spacing: 10) {
                        if service.appsLoading {
                            ProgressView().controlSize(.small)
                            Text(text.stillLooking)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                            Text(text.noResultsTitle)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 16) {
                Text(message ?? text.shortcutCaptureHint)
                    .font(.caption)
                    .foregroundStyle(message == nil ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(l10n.s.supportIntroDoneButton) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 780, height: 560)
        .onAppear { service.refreshApplications() }
        .onChange(of: features.revision) { _, _ in
            if !AppFeature.commandBar.isAvailable { dismiss() }
        }
        .onChange(of: l10n.language) { _, _ in message = nil }
    }

    private func visibleApps(shortcuts: [String: GlobalShortcut], aliases: [String: String],
                             pins: Set<String>) -> [CommandBarEntry] {
        let query = CommandBarSearch.normalized(query)
        // Several installed copies share one durable binding. Show that
        // binding once, using the same last entry the service launches.
        let entries = service.appEntries.reversed()
        let unique = CommandBarSearch.firstOccurrences(of: entries.map(\.stableKey))
        let candidates = Array(entries)
        return unique.map { candidates[$0] }.filter { entry in
            let included = filter == .all
                || (filter == .pinned && pins.contains(entry.stableKey))
                || (filter == .shortcuts && shortcuts[entry.stableKey] != nil)
            return included && (query.isEmpty || CommandBarSearch.normalized(
                "\(entry.title) \(entry.keywords) \(aliases[entry.stableKey] ?? "")").contains(query))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func shortcutField(for entry: CommandBarEntry, shortcut: GlobalShortcut?) -> some View {
        HStack(spacing: 4) {
            ShortcutRecorderButton(
                shortcut: shortcut ?? .commandBarDefault,
                isEnabled: AppFeature.commandBar.isAvailable,
                waitingTitle: l10n.s.shortcutPressKeys,
                emptyTitle: shortcut == nil ? text.appShortcutRecord : nil,
                clearAction: { report(service.setRowShortcut(nil, for: entry), for: entry) },
                notCapturedAction: { report(l10n.s.shortcutNotCaptured, for: entry) },
                recordingChanged: { if $0 { message = nil } },
                invalidAction: { report(l10n.s.shortcutInvalid, for: entry) },
                captureAction: { report(service.setRowShortcut($0, for: entry), for: entry) })
                .frame(width: 140)
                .accessibilityLabel("\(entry.title): \(text.appShortcutLabel)")
            if service.refusedRowShortcutKeys.contains(entry.stableKey) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(l10n.s.shortcutUnavailable)
                    .accessibilityLabel(l10n.s.shortcutUnavailable)
            }
            if shortcut != nil {
                Button { report(service.setRowShortcut(nil, for: entry), for: entry) } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help(text.actionShortcutRemove)
                .accessibilityLabel("\(entry.title): \(text.actionShortcutRemove)")
            }
        }
    }

    private func report(_ error: String?, for entry: CommandBarEntry) {
        message = error.map { "\(entry.title): \($0)" }
    }
}

private struct CommandBarAppAliasField: View {
    let entry: CommandBarEntry
    let savedAlias: String
    let text: CommandBarFeatureStrings
    let report: (String?) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text.aliasPlaceholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .accessibilityLabel("\(entry.title): \(text.appAliasLabel)")
            .onAppear { draft = savedAlias }
            .onChange(of: savedAlias) { _, value in if !focused { draft = value } }
            .onChange(of: focused) { _, value in if !value { save() } }
            .onSubmit(save)
            .onDisappear(perform: save)
    }

    private func save() {
        guard draft != savedAlias, AppFeature.commandBar.isAvailable else { return }
        let service = CommandBarService.shared
        let alias = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if let owner = service.rowAlreadyNamed(alias, excluding: entry) {
            report(String(format: text.aliasTakenFormat, owner))
            draft = savedAlias
            return
        }
        service.setAlias(alias, for: entry)
        draft = alias
        report(nil)
    }
}
