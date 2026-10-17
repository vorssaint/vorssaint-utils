// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

struct FinderToolsConfigurationView: View {
    @ObservedObject var service: FinderToolsService
    @ObservedObject private var l10n = L10n.shared
    @State private var kind: FinderToolsSavedAction.Kind = .folder
    @State private var name = ""
    @State private var location = ""
    @State private var invalid = false
    @State private var editingID: UUID?
    @State private var group = ""
    private var labels: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    FinderToolsSetupView()
                    Divider()
                    ForEach(FinderCreationSetting.allCases) { setting in
                        Toggle(setting.title(l10n.language.rawValue), isOn: Binding(get: {
                            (service.configuration.creation ?? FinderCreationPreferences())[keyPath: setting.keyPath]
                        }, set: { value in
                            var creation = service.configuration.creation ?? FinderCreationPreferences()
                            creation[keyPath: setting.keyPath] = value
                            service.configuration.creation = creation
                        }))
                    }
                    Divider()
                    Toggle(labels.kindSubmenu, isOn: $service.configuration.menu.grouped)
                    ForEach(service.configuration.menu.orderedActions) { action in
                        VStack(alignment: .leading) {
                          HStack {
                            Toggle("", isOn: Binding(get: {
                                !service.configuration.menu.hidden.contains(action.rawValue)
                            }, set: { enabled in
                                if enabled { service.configuration.menu.hidden.remove(action.rawValue) }
                                else { service.configuration.menu.hidden.insert(action.rawValue) }
                            }))
                            .labelsHidden()
                            .accessibilityLabel(action.title(languageCode: l10n.language.rawValue))
                            TextField(action.title(languageCode: l10n.language.rawValue), text: Binding(get: {
                                service.configuration.menu.titles[action.rawValue] ?? ""
                            }, set: { service.configuration.menu.titles[action.rawValue] = String($0.prefix(80)) }))
                            Button("↑") { service.configuration.menu.move(action, by: -1) }
                            Button("↓") { service.configuration.menu.move(action, by: 1) }
                          }
                          DisclosureGroup(labels.iconLabel + " · " + labels.kindShortcut) {
                            TextField(labels.iconLabel + " (SF Symbols)", text: Binding(get: {
                                service.configuration.menu.icons?[action.rawValue] ?? ""
                            }, set: { value in
                                var icons = service.configuration.menu.icons ?? [:]
                                icons[action.rawValue] = String(value.prefix(80))
                                service.configuration.menu.icons = icons
                            }))
                            TextField(labels.kindShortcut + " (⇧⌘)", text: Binding(get: {
                                service.configuration.menu.shortcuts?[action.rawValue] ?? ""
                            }, set: { value in
                                var shortcuts = service.configuration.menu.shortcuts ?? [:]
                                shortcuts[action.rawValue] = String(value.lowercased().prefix(1))
                                service.configuration.menu.shortcuts = shortcuts
                            }))
                          }.font(.caption)
                        }
                    }
                }.padding()
            }.tabItem { Text(l10n.s.menuSettings) }
            VStack(alignment: .leading, spacing: 12) {
                List {
                    ForEach(Array(service.configuration.savedActions.enumerated()), id: \.element.id) { index, action in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(action.title)
                                Text(action.location.absoluteString).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { edit(action) } label: { Image(systemName: "pencil") }
                                .accessibilityLabel(action.title)
                            Button("↑") { service.configuration.savedActions.swapAt(index, index - 1) }.disabled(index == 0)
                            Button("↓") { service.configuration.savedActions.swapAt(index, index + 1) }
                                .disabled(index + 1 == service.configuration.savedActions.count)
                            Button(l10n.s.actionRemove) {
                                service.configuration.savedActions.removeAll { $0.id == action.id }
                                if editingID == action.id { clearEditor() }
                            }
                        }
                    }
                }
                Form {
                    Picker(labels.actionLabel, selection: $kind) {
                        Text(FinderToolsCategory.files.title(language: l10n.language.rawValue)).tag(FinderToolsSavedAction.Kind.folder)
                        Text(labels.kindApp).tag(FinderToolsSavedAction.Kind.application)
                        Text(FinderToolsAction.template.title(languageCode: l10n.language.rawValue)).tag(FinderToolsSavedAction.Kind.template)
                        Text("Shell / AppleScript / Python").tag(FinderToolsSavedAction.Kind.script)
                        Text(labels.kindURL).tag(FinderToolsSavedAction.Kind.website)
                        Text(labels.iconLabel).tag(FinderToolsSavedAction.Kind.icon)
                    }
                    TextField(labels.nameLabel, text: $name)
                    TextField(labels.kindSubmenu, text: $group)
                    HStack {
                        TextField(kind == .website ? labels.urlPlaceholder : labels.kindFile, text: $location)
                        if kind != .website { Button(labels.chooseButton) { chooseFile() } }
                    }
                }
                if invalid { Text(FinderToolsStrings.localized(l10n.language).failure).foregroundStyle(.red) }
                HStack {
                    Button(editingID == nil ? labels.addButton : labels.saveButton) { addAction() }
                        .disabled(location.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if editingID != nil { Button(FinderToolsStrings.localized(l10n.language).cancel) { clearEditor() } }
                }
            }.padding().tabItem { Text(labels.actionsHeader) }
        }.padding(12).frame(minWidth: 580, minHeight: 480)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = kind == .folder || kind == .template
        panel.canChooseFiles = kind != .folder
        if kind == .application { panel.allowedContentTypes = [.applicationBundle] }
        if kind == .icon { panel.allowedContentTypes = [.image] }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            location = url.path
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        }
    }

    private func addAction() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL?
        if kind == .website {
            url = URL(string: location).flatMap { ["https", "http"].contains($0.scheme) && $0.host != nil ? $0 : nil }
        } else {
            url = location.hasPrefix("/") ? URL(fileURLWithPath: location) : nil
        }
        guard let url, editingID != nil || service.configuration.savedActions.count < 200 else {
            invalid = true
            return
        }
        let groupName = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = FinderToolsSavedAction(id: editingID ?? UUID(), title: title, kind: kind,
                                           location: url, group: groupName.isEmpty ? nil : groupName)
        guard action.isValid else { invalid = true; return }
        if let index = service.configuration.savedActions.firstIndex(where: { $0.id == editingID }) {
            service.configuration.savedActions[index] = action
        } else { service.configuration.savedActions.append(action) }
        clearEditor()
    }

    private func edit(_ action: FinderToolsSavedAction) {
        editingID = action.id
        name = action.title
        kind = action.kind
        location = action.location.isFileURL ? action.location.path : action.location.absoluteString
        group = action.group ?? ""
        invalid = false
    }

    private func clearEditor() {
        editingID = nil
        name = ""
        location = ""
        group = ""
        invalid = false
    }
}
