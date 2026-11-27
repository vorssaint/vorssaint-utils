// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// A section of the existing Finder settings page, not a separate utility UI.
struct FinderNewFileSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.finderNewFileEnabled) private var enabled = false
    @AppStorage(DefaultsKey.finderNewFileKinds) private var selection = FinderNewFileKind.defaultSelection
    @AppStorage(DefaultsKey.finderNewFileCustomItems) private var customRaw = "[]"
    @State private var editing: FinderNewFileCustomItem?

    private var customItems: [FinderNewFileCustomItem] { FinderNewFileCustomItem.decode(customRaw) }

    private var strings: FinderNewFileStrings {
        FeatureStrings.finderNewFile(l10n.language)
    }

    var body: some View {
        Section {
            Toggle(strings.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in FinderNewFileService.syncWithPreferences() }
            Text(strings.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            FinderNewFileExtensionStatus()
            if enabled {
                ForEach(FinderNewFileKind.allCases, id: \.self) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label(kind.title(strings), systemImage: kind.symbol)
                    }
                }
                customDocuments
            }
        } header: {
            Text(strings.title)
        }
        .settingsFormSectionAnchor(.finderNewFile)
        .onChange(of: selection) { _, _ in FinderNewFileService.syncWithPreferences() }
        .onChange(of: customRaw) { _, _ in FinderNewFileService.syncWithPreferences() }
        .sheet(item: $editing) { item in
            FinderNewFileCustomEditor(draft: item) { saved in
                save(saved)
                editing = nil
            } cancel: {
                editing = nil
            }
        }
    }

    private var customDocuments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.customTitle).font(.subheadline.weight(.medium))
            ForEach(customItems) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                        Text(item.outputName + " · " + (item.template?.name ?? strings.emptyTemplate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button { editing = item } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain)
                        .help(l10n.s.menuEdit)
                        .accessibilityLabel(l10n.s.menuEdit + ": " + item.title)
                    Button { remove(item) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .help(l10n.s.actionRemove)
                        .accessibilityLabel(l10n.s.actionRemove + ": " + item.title)
                }
            }
            Button(strings.addItem) { editing = FinderNewFileCustomItem() }
                .disabled(customItems.count >= FinderNewFileCustomItem.maximum)
        }
    }

    private func save(_ item: FinderNewFileCustomItem) {
        var items = customItems
        var previous: FinderNewFileCustomItem.Template?
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            previous = items[index].template
            items[index] = item
        } else {
            items.append(item)
        }
        customRaw = FinderNewFileCustomItem.encode(items)
        FinderNewFileService.syncWithPreferences()
        if let previous, previous.id != item.template?.id,
           !items.contains(where: { $0.template?.id == previous.id }) {
            FinderNewFileTemplateStore.remove(previous)
        }
    }

    private func remove(_ item: FinderNewFileCustomItem) {
        let items = customItems.filter { $0.id != item.id }
        customRaw = FinderNewFileCustomItem.encode(items)
        FinderNewFileService.syncWithPreferences()
        if let template = item.template,
           !items.contains(where: { $0.template?.id == template.id }) {
            FinderNewFileTemplateStore.remove(template)
        }
    }

    private func binding(for kind: FinderNewFileKind) -> Binding<Bool> {
        Binding(get: { FinderNewFileKind.selection(selection).contains(kind) },
                set: { value in
                    var kinds = Set(FinderNewFileKind.selection(selection))
                    if value { kinds.insert(kind) } else { kinds.remove(kind) }
                    selection = FinderNewFileKind.allCases.filter { kinds.contains($0) }
                        .map(\.rawValue).joined(separator: ",")
                })
    }
}

/// Edits a draft, committing preferences and template imports only on Save.
private struct FinderNewFileCustomEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @State var draft: FinderNewFileCustomItem
    @State private var selectedFile: URL?
    @State private var error: String?
    let save: (FinderNewFileCustomItem) -> Void
    let cancel: () -> Void

    private var strings: FinderNewFileStrings { FeatureStrings.finderNewFile(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(strings.customTitle).font(.system(size: 15, weight: .semibold))
            field(strings.menuName, text: $draft.title)
            field(strings.fileName, text: $draft.filename)
            field(strings.suffixLabel, text: $draft.suffix)
            if let valid = draft.normalized {
                Text(valid.outputName)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(strings.invalidItem).font(.caption).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(strings.templateLabel).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(selectedFile?.lastPathComponent ?? draft.template?.name ?? strings.emptyTemplate)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(FeatureStrings.radialMenu(l10n.language).chooseButton) { chooseFile() }
                    if selectedFile != nil || draft.template != nil {
                        Button(l10n.s.actionRemove) {
                            selectedFile = nil
                            draft.template = nil
                            error = nil
                        }
                    }
                }
                Text(strings.templateHelp)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(strings.cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(FeatureStrings.snippets(l10n.language).saveButton) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.normalized == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFile = url
        error = nil
        let base = url.deletingPathExtension().lastPathComponent
        if draft.title.isEmpty { draft.title = base }
        if draft.filename == "Untitled" || draft.filename.isEmpty { draft.filename = base }
        if draft.suffix.isEmpty { draft.suffix = url.pathExtension }
    }

    private func commit() {
        guard var item = draft.normalized else { return }
        do {
            if let selectedFile {
                item.template = try FinderNewFileTemplateStore.importFile(selectedFile)
            }
            save(item)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Mirrors PermissionRow's status and actions without treating a Finder
/// extension as a TCC permission. The management entry stays available even
/// when the feature switch is off, so the user can disable the extension.
struct FinderNewFileExtensionStatus: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var extensionEnabled: Bool?
    @State private var refreshID = UUID()

    private var strings: FinderNewFileStrings {
        FeatureStrings.finderNewFile(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let enabled = extensionEnabled {
                    Image(systemName: enabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(enabled ? .green : .orange)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(strings.extensionName)
                Spacer()
                if let enabled = extensionEnabled {
                    Text(enabled ? strings.extensionEnabled : strings.extensionDisabled)
                        .font(.caption)
                        .foregroundStyle(enabled ? .green : .orange)
                }
            }
            if extensionEnabled == false {
                Text(strings.extensionHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(strings.manage) {
                FinderNewFileService.openExtensionSettings()
            }
            .controlSize(.small)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        // Match WindowLayoutSettings' appearance/activation refresh policy.
        // Like the permission portal's automation check, keep the system
        // query off the UI thread. No separate periodic monitor is needed.
        let id = UUID()
        refreshID = id
        DispatchQueue.global(qos: .userInitiated).async {
            let enabled = FinderNewFileService.extensionEnabled
            DispatchQueue.main.async {
                guard refreshID == id else { return }
                extensionEnabled = enabled
            }
        }
    }
}
