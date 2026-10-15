// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The browser that opens web links now, the others to switch to, and the
/// shortcut that moves between the chosen ones.
struct DefaultBrowserSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DefaultBrowserService.shared
    @AppStorage(DefaultsKey.defaultBrowserShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.notchDefaultBrowser) private var islandNotice = true
    @State private var rotation: [String] = []

    private var strings: DefaultBrowserFeatureStrings { FeatureStrings.defaultBrowser(l10n.language) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Text(strings.current)
                    Spacer()
                    if let current = service.current {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: current.path))
                            .resizable().frame(width: 18, height: 18)
                        Text(FileManager.default.displayName(atPath: current.path)).foregroundStyle(.secondary)
                    } else {
                        Text(strings.none).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if service.browsers.isEmpty {
                    Text(strings.empty).foregroundStyle(.secondary)
                }
                ForEach(service.browsers) { browser in
                    row(browser)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.confirmNote)
                    if let failure = service.failure {
                        Text(failure).foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        DefaultBrowserService.shared.syncWithPreferences()
                    }
                ShortcutPreferenceRow(role: .defaultBrowser, isEnabled: shortcutEnabled) {
                    DefaultBrowserService.shared.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(strings.rotationCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(strings.islandNotice, isOn: $islandNotice)
            } header: {
                Text(strings.nextBrowser)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rotation = UserDefaults.standard.stringArray(forKey: DefaultsKey.defaultBrowserRotation) ?? []
            service.reload()
        }
        // A change made in System Settings shows up when coming back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.reload()
        }
    }

    private func row(_ browser: DefaultBrowserSupport.Browser) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { rotation.contains(browser.bundleID) },
                set: { setInRotation(browser.bundleID, $0) }
            )) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(strings.inRotation)
                .accessibilityLabel(strings.inRotation)
            Image(nsImage: NSWorkspace.shared.icon(forFile: browser.url.path))
                .resizable().frame(width: 22, height: 22)
            Text(browser.name)
            Spacer()
            if service.isCurrent(browser) {
                Label(strings.isDefault, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(strings.makeDefault) { service.makeDefault(browser) }
                    .disabled(service.changing)
            }
        }
    }

    /// Kept in the order the browsers are listed, so the shortcut goes down
    /// the list the user sees.
    private func setInRotation(_ bundleID: String, _ included: Bool) {
        var chosen = Set(rotation)
        if included { chosen.insert(bundleID) } else { chosen.remove(bundleID) }
        let listed = service.browsers.map(\.bundleID)
        rotation = listed.filter(chosen.contains) + chosen.subtracting(listed).sorted()
        UserDefaults.standard.set(rotation, forKey: DefaultsKey.defaultBrowserRotation)
    }
}
