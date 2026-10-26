// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pick an app, then make it the default for formats it declares it opens.
struct DefaultAppsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var app: URL?
    @State private var formats: [UTType] = []
    /// The app macOS opens each format with, by type identifier.
    @State private var owners: [String: URL] = [:]
    @State private var selection: Set<String> = []
    @State private var failures: [String: String] = [:]
    @State private var expanded: Set<DefaultAppsSupport.Category> = []
    @State private var applying = false

    private var strings: DefaultAppsFeatureStrings { FeatureStrings.defaultApps(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(strings.title).font(.title2.bold())
                SettingsCard {
                    SettingsRow(symbol: "app.badge", title: strings.openWith, caption: strings.openWithCaption) {
                        HStack(spacing: 10) {
                            Text(app.map(Self.name) ?? strings.noApp).foregroundStyle(.secondary)
                            Button(strings.chooseApp, action: chooseApp).disabled(applying)
                        }
                    }
                    if app != nil {
                        Divider()
                        if formats.isEmpty {
                            Text(strings.noFormats).font(.callout).foregroundStyle(.secondary)
                        } else {
                            ForEach(groups, id: \.0) { category, types in
                                group(category, types)
                            }
                            Divider()
                            footer
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .onAppear(perform: reload)
    }

    private var groups: [(DefaultAppsSupport.Category, [UTType])] {
        let byCategory = Dictionary(grouping: formats, by: DefaultAppsSupport.category(of:))
        return DefaultAppsSupport.Category.allCases.compactMap { category in
            byCategory[category].map { (category, $0) }
        }
    }

    private func group(_ category: DefaultAppsSupport.Category, _ types: [UTType]) -> some View {
        let selectable = types.map(\.identifier).filter { owners[$0].map(isChosenApp) != true }
        // A long group opens folded so the other groups stay in view.
        let folded = types.count > 8 && !expanded.contains(category)
        let shown = folded ? Array(types.prefix(5)) : types
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { !selectable.isEmpty && selection.isSuperset(of: selectable) },
                set: { if $0 { selection.formUnion(selectable) } else { selection.subtract(selectable) } }
            )) {
                HStack(spacing: 6) {
                    Text(strings.name(of: category)).font(.headline)
                    Text("\(types.count)").foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(selectable.isEmpty || applying)
            ForEach(shown, id: \.identifier) { type in
                row(type)
            }
            if folded {
                Button(String(format: strings.moreFormat, types.count - shown.count)) {
                    expanded.insert(category)
                }
                .buttonStyle(.link)
                .padding(.leading, 22)
            }
        }
    }

    private func row(_ type: UTType) -> some View {
        let id = type.identifier
        let owner = owners[id]
        let owned = owner.map(isChosenApp) == true
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { selection.contains(id) },
                    set: { if $0 { selection.insert(id) } else { selection.remove(id) } }
                )) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(owned || applying)
                Text("." + (type.preferredFilenameExtension ?? ""))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 70, alignment: .leading)
                Text(type.localizedDescription ?? id)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(owned ? String(format: strings.alreadyFormat, Self.name(owner!))
                     : owner.map { String(format: strings.currentFormat, Self.name($0)) } ?? strings.currentNone)
                    .font(.caption)
                    .foregroundStyle(owned ? .green : .secondary)
            }
            if let failure = failures[id] {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .padding(.leading, 22)
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 10) {
                Text(String(format: strings.selectedFormat, selection.count)).foregroundStyle(.secondary)
                Spacer()
                if applying { ProgressView().controlSize(.small) }
                Button(strings.setDefault, action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || applying)
            }
            Text(strings.confirmNote).font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func name(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }

    /// LaunchServices records defaults by bundle identifier, so another copy
    /// of the same app at a different path already counts as the chosen one.
    private func isChosenApp(_ url: URL) -> Bool {
        guard let app else { return false }
        if let id = Bundle(url: app)?.bundleIdentifier, id == Bundle(url: url)?.bundleIdentifier { return true }
        return url.standardizedFileURL == app.standardizedFileURL
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app = url
        selection = []
        failures = [:]
        expanded = []
        reload()
    }

    /// Reads the formats and their current apps again. An app that was moved
    /// or deleted since it was chosen is dropped rather than shown as if it
    /// could still take formats.
    private func reload() {
        guard let app else { return }
        guard FileManager.default.fileExists(atPath: app.path) else {
            self.app = nil
            formats = []
            selection = []
            failures = [:]
            return
        }
        formats = DefaultAppsSupport.declaredTypes(infoDictionary: Bundle(url: app)?.infoDictionary ?? [:])
        owners = Dictionary(uniqueKeysWithValues: formats.compactMap { type in
            NSWorkspace.shared.urlForApplication(toOpen: type).map { (type.identifier, $0) }
        })
        selection.formIntersection(formats.map(\.identifier))
    }

    /// One type at a time: macOS may ask the user to confirm each change in
    /// its own dialog, and declining one stops the rest of the batch.
    private func apply() {
        // Not a full reload: owners read now could undo the ones just set.
        guard let app, FileManager.default.fileExists(atPath: app.path) else { return reload() }
        let pending = groups.flatMap(\.1).filter { selection.contains($0.identifier) }
        applying = true
        Task { @MainActor in
            for type in pending {
                let id = type.identifier
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                    // Right after a change, LaunchServices can still answer
                    // this process with the previous app, so it is not read back.
                    owners[id] = app
                    selection.remove(id)
                    failures[id] = nil
                } catch {
                    let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
                    if underlying?.domain == NSOSStatusErrorDomain && underlying?.code == Int(userCanceledErr) {
                        break
                    }
                    failures[id] = error.localizedDescription
                }
            }
            applying = false
        }
    }
}
