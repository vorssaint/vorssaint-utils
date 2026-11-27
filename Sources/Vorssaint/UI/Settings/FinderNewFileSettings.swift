// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// A section of the existing Finder settings page, not a separate utility UI.
struct FinderNewFileSettings: View {
    private static let reorderType = UTType(exportedAs: "com.vorssaint.utils.finder-new-file.reorder")
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.finderNewFileEnabled) private var enabled = false
    @AppStorage(DefaultsKey.finderNewFileItems) private var raw = ""
    @State private var editing: FinderNewFileItem?
    @State private var dragging: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var strings: FinderNewFileStrings { FeatureStrings.finderNewFile(l10n.language) }

    private var items: [FinderNewFileItem] {
        FinderNewFileService.configuredItems(raw: raw)
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
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                            .onDrop(of: [Self.reorderType], delegate: FinderNewFileOrderDropDelegate(
                                target: item.id, dragging: $dragging, move: move))
                        if item.id != items.last?.id { Divider().padding(.leading, 24) }
                    }
                }
                Button(strings.addItem) {
                    editing = FinderNewFileItem()
                }
                .disabled(items.filter(\.canDelete).count >= FinderNewFileItem.maximum)
            }
        } header: {
            Text(strings.title)
        }
        .settingsFormSectionAnchor(.finderNewFile)
        .onDisappear { dragging = nil }
        .sheet(item: $editing) { item in
            FinderNewFileDocumentEditor(draft: item, isNew: !items.contains(where: { $0.id == item.id })) { saved in
                save(saved)
                editing = nil
            } cancel: {
                editing = nil
            }
        }
    }

    private func row(_ item: FinderNewFileItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .contentShape(Rectangle())
                .onDrag {
                    dragging = item.id
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: Self.reorderType.identifier,
                                                        visibility: .ownProcess) { completion in
                        completion(Data(item.id.uuidString.utf8), nil)
                        return nil
                    }
                    return provider
                }
            Image(systemName: item.symbol).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.menuTitle(strings))
                Text(item.outputName + " · " + (item.template?.name ??
                    (item.hasBuiltInContent ? strings.defaultContent : strings.emptyTemplate)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if item.canDelete {
                Button { remove(item) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .help(l10n.s.actionRemove)
                    .accessibilityLabel(l10n.s.actionRemove + ": " + item.displayName(strings))
                    .frame(width: 18)
            }
            Button { editing = item } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help(l10n.s.menuEdit)
                .accessibilityLabel(l10n.s.menuEdit + ": " + item.displayName(strings))
                .frame(width: 18)
            Toggle(isOn: Binding(get: {
                items.first(where: { $0.id == item.id })?.isEnabled ?? false
            }, set: { value in
                var updated = items
                guard let index = updated.firstIndex(where: { $0.id == item.id }) else { return }
                updated[index].enabled = value
                persist(updated)
            })) {
                Text(item.displayName(strings))
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func persist(_ items: [FinderNewFileItem]) {
        raw = FinderNewFileItem.encode(items)
        FinderNewFileService.syncWithPreferences()
    }

    private func move(_ source: UUID, _ target: UUID) {
        let current = items
        let updated = FinderNewFileItem.reordered(current, moving: source, to: target)
        guard updated != current else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
            persist(updated)
        }
    }

    private func save(_ item: FinderNewFileItem) {
        var updated = items
        var previous: FinderNewFileItem.Template?
        if let index = updated.firstIndex(where: { $0.id == item.id }) {
            previous = updated[index].template
            updated[index] = item
        } else {
            guard item.canDelete, updated.filter(\.canDelete).count < FinderNewFileItem.maximum else { return }
            updated.append(item)
        }
        persist(updated)
        if let previous, previous.id != item.template?.id,
           !updated.contains(where: { $0.template?.id == previous.id }) {
            FinderNewFileTemplateStore.remove(previous)
        }
    }

    private func remove(_ item: FinderNewFileItem) {
        guard item.canDelete else { return }
        let updated = items.filter { $0.id != item.id }
        persist(updated)
        if let template = item.template,
           !updated.contains(where: { $0.template?.id == template.id }) {
            FinderNewFileTemplateStore.remove(template)
        }
    }
}

private struct FinderNewFileOrderDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        move(dragging, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragging == nil ? .forbidden : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard dragging != nil else { return false }
        dragging = nil
        return true
    }
}

/// Edits a draft, committing preferences and template imports only on Save.
private struct FinderNewFileDocumentEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var draft: FinderNewFileItem
    @State private var menuName: String
    @State private var selectedFile: URL?
    @State private var error: String?
    let isNew: Bool
    let save: (FinderNewFileItem) -> Void
    let cancel: () -> Void

    init(draft: FinderNewFileItem, isNew: Bool, save: @escaping (FinderNewFileItem) -> Void,
         cancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        _menuName = State(initialValue: draft.displayName(FeatureStrings.finderNewFile(L10n.shared.language)))
        self.isNew = isNew
        self.save = save
        self.cancel = cancel
    }

    private var strings: FinderNewFileStrings { FeatureStrings.finderNewFile(l10n.language) }

    private var candidate: FinderNewFileItem? {
        var item = draft
        let name = menuName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        item.title = name == draft.builtIn?.name(strings) ? "" : name
        return item.normalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? strings.addItem : l10n.s.menuEdit).font(.system(size: 15, weight: .semibold))
            field(strings.menuName, text: $menuName)
            field(strings.fileName, text: $draft.filename)
            field(strings.suffixLabel, text: $draft.suffix)
            if let valid = candidate {
                Text(valid.outputName)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(strings.invalidItem).font(.caption).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(strings.templateLabel).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(selectedFile?.lastPathComponent ?? draft.template?.name ??
                         (draft.hasBuiltInContent ? strings.defaultContent : strings.emptyTemplate))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(FeatureStrings.radialMenu(l10n.language).chooseButton) { chooseFile() }
                    if selectedFile != nil || draft.template != nil || draft.hasBuiltInContent {
                        Button(l10n.s.actionRemove) {
                            selectedFile = nil
                            draft.template = nil
                            draft.useBuiltInContent = false
                            error = nil
                        }
                    }
                }
                if draft.builtIn != nil && (selectedFile != nil || !draft.hasBuiltInContent) {
                    Button(strings.defaultContent) {
                        selectedFile = nil
                        draft.template = nil
                        draft.useBuiltInContent = true
                        error = nil
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
                    .disabled(candidate == nil)
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
        // A template supplies content only. Never change the independently
        // configured menu name, filename or suffix, even on a new entry.
    }

    private func commit() {
        guard var item = candidate else { return }
        do {
            if let selectedFile {
                item.template = try FinderNewFileTemplateStore.importFile(selectedFile)
                item.useBuiltInContent = false
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
