// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MenuBarOrganizerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var organizer = MenuBarOrganizerService.shared
    @AppStorage(DefaultsKey.menuBarOrganizerEnabled) private var enabled = false
    @State private var search = ""

    var body: some View {
        let text = MenuBarOrganizerStrings.localized(l10n.language)
        SettingsCard(title: text.title) {
            SettingsRow(symbol: "menubar.rectangle", title: text.enabled, caption: text.enabledCaption) {
                Toggle(text.enabled, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            Text(organizer.usesNativeVisibility ? text.nativeInstructions : text.arrangeHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                ViewThatFits {
                    HStack {
                        controls(text)
                    }
                    VStack(alignment: .leading) {
                        controls(text)
                    }
                }
                if organizer.isUpdating {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(text.updating).font(.caption)
                    }
                }
                if organizer.usesNativeVisibility {
                    Text(text.modernSystemHint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    applicationSections(text)
                }
                if !organizer.accessibilityAvailable {
                    Text(text.accessibilityNeeded).font(.caption).foregroundStyle(.secondary)
                    Button(text.grantAccessibility) { Permissions.shared.requestAccessibility() }
                }
                if organizer.failure != nil {
                    Text(organizer.failureMessage)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: enabled) { _, enabled in organizer.setEnabled(enabled) }
        .onAppear { organizer.refreshApplications() }
    }

    @ViewBuilder private func controls(_ text: MenuBarOrganizerStrings) -> some View {
        Button(organizer.presentedSection == .hidden ? text.hideSection : text.showSection) {
            organizer.toggleHiddenSection()
        }
        Button(organizer.presentedSection == .alwaysHidden ? text.hideAlwaysHidden : text.showAlwaysHidden) {
            organizer.toggleAlwaysHiddenSection()
        }
        Button(text.revealAll) { organizer.revealAll() }
    }

    private func applicationSections(_ text: MenuBarOrganizerStrings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.applications).font(.subheadline.weight(.semibold))
            TextField(text.search, text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(organizer.applications.filter { app in
                        search.isEmpty || (app.localizedName ?? "").localizedCaseInsensitiveContains(search)
                            || (app.bundleIdentifier ?? "").localizedCaseInsensitiveContains(search)
                    }, id: \.bundleIdentifier) { app in
                        if let bundle = app.bundleIdentifier {
                            HStack {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                }
                                Text(app.localizedName ?? bundle).lineLimit(1)
                                Spacer()
                                Picker(app.localizedName ?? bundle, selection: Binding(
                                    get: { organizer.section(for: bundle) },
                                    set: { organizer.setSection($0, for: bundle) })) {
                                    Text(text.visible).tag(MenuBarOrganizerSection.visible)
                                    Text(text.hiddenSection).tag(MenuBarOrganizerSection.hidden)
                                    Text(text.alwaysHiddenSection).tag(MenuBarOrganizerSection.alwaysHidden)
                                }.labelsHidden().frame(width: 170)
                            }
                        }
                    }
                }.padding(4)
            }.frame(height: 200)
        }
    }
}
