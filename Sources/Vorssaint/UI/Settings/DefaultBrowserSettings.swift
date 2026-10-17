// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The browser that opens web links now, and the others to switch to.
struct DefaultBrowserSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var browsers: [DefaultBrowserSupport.Browser] = []
    @State private var current: URL?
    @State private var changing = false
    @State private var failure: String?

    private var strings: DefaultBrowserFeatureStrings { FeatureStrings.defaultBrowser(l10n.language) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Text(strings.current)
                    Spacer()
                    if let current {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: current.path))
                            .resizable().frame(width: 18, height: 18)
                        Text(FileManager.default.displayName(atPath: current.path)).foregroundStyle(.secondary)
                    } else {
                        Text(strings.none).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if browsers.isEmpty {
                    Text(strings.empty).foregroundStyle(.secondary)
                }
                ForEach(browsers) { browser in
                    row(browser)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.confirmNote)
                    if let failure {
                        Text(failure).foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        // A change made in System Settings shows up when coming back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !changing { reload() }
        }
    }

    private func row(_ browser: DefaultBrowserSupport.Browser) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: browser.url.path))
                .resizable().frame(width: 22, height: 22)
            Text(browser.name)
            Spacer()
            if isCurrent(browser) {
                Label(strings.isDefault, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(strings.makeDefault) { makeDefault(browser) }
                    .disabled(changing)
            }
        }
    }

    /// Launch Services records the default by bundle id, so another copy of
    /// the same browser already counts as the default.
    private func isCurrent(_ browser: DefaultBrowserSupport.Browser) -> Bool {
        guard let current else { return false }
        return Bundle(url: current)?.bundleIdentifier == browser.bundleID
            || current.standardizedFileURL == browser.url
    }

    private func reload() {
        browsers = DefaultBrowserSupport.installed()
        current = DefaultBrowserSupport.current
    }

    private func makeDefault(_ browser: DefaultBrowserSupport.Browser) {
        changing = true
        failure = nil
        Task { @MainActor in
            do {
                try await DefaultBrowserSupport.makeDefault(browser.url)
                // Right after a change Launch Services can still answer this
                // process with the previous browser, so it is not read back.
                current = browser.url
            } catch {
                if !DefaultBrowserSupport.isCancellation(error) { failure = error.localizedDescription }
                // http may have changed before https was declined.
                reload()
            }
            changing = false
        }
    }
}
