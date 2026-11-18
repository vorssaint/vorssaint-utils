// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan
import AppKit
import SwiftUI

struct NotchLauncherSettings: View {
    @ObservedObject private var launcher = IslandLauncherService.shared
    @ObservedObject private var websiteIcons = WebsiteShortcutIconService.shared
    @AppStorage(DefaultsKey.notchQuickAccessLayout) private var layoutData = Data()
    @ObservedObject private var l10n = L10n.shared
    @State private var addingWebsite = false
    @State private var crossOverApps: [IslandLauncherService.Candidate] = []
    private var strings: NotchShortcutStrings { .localized(l10n.language) }

    var body: some View {
        SettingsCard(title: strings.title) {
            Text(strings.hint)
                .font(.callout).foregroundStyle(.secondary)
            if launcher.entries.isEmpty { Text(strings.empty).foregroundStyle(.secondary) }
            ForEach(Array(launcher.entries.enumerated()), id: \.element.id) { index, entry in
                HStack {
                    if let url = launcher.resolvedURL(entry) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(
                            width: 24, height: 24)
                    } else if entry.website != nil {
                        Group {
                            if let image = websiteIcons.icons[entry.id] {
                                WebsiteShortcutIcon(
                                    image: image, lightBackground: websiteIcons.darkIcons.contains(entry.id), size: 24)
                            } else {
                                Image(systemName: "globe").resizable().scaledToFit().padding(3)
                            }
                        }.frame(width: 24, height: 24).onAppear { websiteIcons.load(entry) }
                    } else {
                        Image(systemName: "exclamationmark.triangle").frame(width: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).lineLimit(1)
                        if let website = entry.website {
                            Text(websiteIcons.loading.contains(entry.id) ? strings.fetching : website)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).help(website)
                            if websiteIcons.failed.contains(entry.id) {
                                Text(websiteIcons.icons[entry.id] == nil ? strings.noIcon : strings.savedIcon)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if entry.website != nil {
                        Button {
                            websiteIcons.load(entry, refresh: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(websiteIcons.loading.contains(entry.id))
                        .accessibilityLabel(strings.refreshIcon + " " + entry.name)
                        .help(strings.refreshIcon)
                    }
                    Picker(
                        FeatureStrings.notchEditor(l10n.language).position + " " + entry.name,
                        selection: Binding<String>(
                            get: {
                                _ = layoutData
                                return launcher.side(for: entry.id)?.rawValue ?? "hidden"
                            },
                            set: { launcher.place(entry.id, on: NotchQuickAccessSide(rawValue: $0)) })
                    ) {
                        Text(strings.notPlaced).tag("hidden")
                        Text(FeatureStrings.notch(l10n.language).quickAccessLeft).tag("left")
                        Text(FeatureStrings.notch(l10n.language).quickAccessRight).tag("right")
                        Text(FeatureStrings.notchEditor(l10n.language).bottom).tag("bottom")
                    }.labelsHidden().frame(width: 110).accessibilityLabel(
                        FeatureStrings.notchEditor(l10n.language).position + " " + entry.name)
                    Button {
                        launcher.move(entry.id, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0).accessibilityLabel(
                        FeatureStrings.clipboard(l10n.language).moveUp + " " + entry.name)
                    Button {
                        launcher.move(entry.id, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index == launcher.entries.count - 1).accessibilityLabel(
                        FeatureStrings.clipboard(l10n.language).moveDown + " " + entry.name)
                    Button {
                        launcher.remove(entry.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .accessibilityLabel(l10n.s.actionRemove + " " + entry.name)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { addButtons }
                VStack(alignment: .leading, spacing: 8) { addButtons }
            }
            Text(strings.slotsHint)
                .font(.caption).foregroundStyle(.secondary)
        }.onAppear { crossOverApps = launcher.crossOverApps() }
            .sheet(isPresented: $addingWebsite) { WebsiteShortcutEditor() }
    }

    @ViewBuilder private var addButtons: some View {
        Button(strings.addApp) { launcher.chooseApp() }
            .disabled(launcher.isChoosing)
        Button(strings.addWebsite) { addingWebsite = true }
        Menu(strings.fromCrossOver) {
            ForEach(crossOverApps) { app in
                Button(app.title) { launcher.add(app.url) }.disabled(launcher.contains(app.url))
            }
        }.disabled(crossOverApps.isEmpty)
    }
}

private struct WebsiteShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    private var strings: NotchShortcutStrings { .localized(l10n.language) }
    @State private var address = ""
    @State private var name = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(strings.addWebsite.replacingOccurrences(of: "…", with: "")).font(.title3.weight(.semibold))
            TextField(strings.url, text: $address, prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder).focused($addressFocused)
                .accessibilityIdentifier("notch.shortcuts.website.address")
            TextField(strings.optionalName, text: $name)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("notch.shortcuts.website.name")
            if !address.isEmpty && IslandLauncherSupport.websiteURL(address) == nil {
                Text(strings.invalidURL)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(strings.privacyHint)
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(FeatureStrings.clipboard(l10n.language).cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(strings.add) {
                    if IslandLauncherService.shared.addWebsite(address, name: name) { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(IslandLauncherSupport.websiteURL(address) == nil)
            }
        }.padding(20).frame(width: 400).onAppear { addressFocused = true }
    }
}
