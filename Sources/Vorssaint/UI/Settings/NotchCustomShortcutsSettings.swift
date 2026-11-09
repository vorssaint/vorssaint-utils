// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchCustomShortcutsSettings: View {
    @AppStorage(DefaultsKey.notchCustomShortcuts) private var data = Data()
    @ObservedObject private var l10n = L10n.shared
    @State private var draft: NotchCustomShortcut?
    @State private var editing = false
    @State private var removing: NotchCustomShortcut?

    private var strings: NotchCustomShortcutStrings { .localized(l10n.language) }
    private var shortcuts: [NotchCustomShortcut] { NotchCustomShortcutSupport.stored() }
    private func destinationTitle(_ destination: NotchShortcutDestination) -> String {
        switch destination {
        case .islandButtons: return FeatureStrings.notchEditor(l10n.language).quickActions
        case .controls: return FeatureStrings.notch(l10n.language).controls
        case .tools: return FeatureStrings.notch(l10n.language).tools
        case .shortcutsPage: return strings.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(strings.title).font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    draft = NotchCustomShortcut(name: "", shortcutName: "", symbol: "bolt.fill")
                    editing = true
                } label: {
                    Label(strings.add, systemImage: "plus")
                }
                .disabled(shortcuts.count >= NotchCustomShortcutSupport.maximumCount)
            }
            if shortcuts.isEmpty {
                Text(strings.empty).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(shortcuts) { shortcut in
                    HStack(spacing: 10) {
                        Image(systemName: shortcut.symbol).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.name).lineLimit(1)
                            Text(shortcut.destinations.map(destinationTitle).joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button {
                            draft = shortcut
                            editing = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help(strings.edit)
                        Button(role: .destructive) { removing = shortcut } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(strings.delete)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .sheet(isPresented: $editing, onDismiss: { draft = nil }) {
            if let draft {
                NotchCustomShortcutEditor(shortcut: draft, strings: strings) { saved in
                    var values = shortcuts
                    if let index = values.firstIndex(where: { $0.id == saved.id }) { values[index] = saved }
                    else { values.append(saved) }
                    data = NotchCustomShortcutSupport.encoded(values)
                }
            }
        }
        .confirmationDialog(strings.delete, isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible) {
            Button(strings.delete, role: .destructive) {
                guard let removing else { return }
                data = NotchCustomShortcutSupport.encoded(shortcuts.filter { $0.id != removing.id })
                self.removing = nil
            }
        }
    }
}

private struct NotchCustomShortcutEditor: View {
    let shortcut: NotchCustomShortcut
    let strings: NotchCustomShortcutStrings
    let save: (NotchCustomShortcut) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var shortcutName: String
    @State private var symbol: String
    @State private var destinations: Set<NotchShortcutDestination>

    init(shortcut: NotchCustomShortcut, strings: NotchCustomShortcutStrings, save: @escaping (NotchCustomShortcut) -> Void) {
        self.shortcut = shortcut
        self.strings = strings
        self.save = save
        _name = State(initialValue: shortcut.name)
        _shortcutName = State(initialValue: shortcut.shortcutName)
        _symbol = State(initialValue: shortcut.symbol)
        _destinations = State(initialValue: Set(shortcut.destinations))
    }

    private var valid: Bool {
        NotchCustomShortcutSupport.isValid(name: name, shortcutName: shortcutName, symbol: symbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(shortcut.name.isEmpty ? strings.add : strings.edit).font(.title2.bold())
            Form {
                TextField(FeatureStrings.notchEditor(l10n.language).buttonName, text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField(strings.shortcutName, text: $shortcutName)
                    .textFieldStyle(.roundedBorder)
                Text(strings.shortcutNameHint).font(.caption).foregroundStyle(.secondary)
                Section(FeatureStrings.notchEditor(l10n.language).destinations) {
                    ForEach(NotchShortcutDestination.allCases) { destination in
                        Toggle(destinationTitle(destination), isOn: Binding(
                            get: { destinations.contains(destination) },
                            set: { enabled in
                                if enabled { destinations.insert(destination) }
                                else { destinations.remove(destination) }
                            }
                        ))
                    }
                }
                HStack {
                    TextField(strings.symbol, text: $symbol)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: symbol.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 20))
                        .frame(width: 28)
                }
                if !symbol.isEmpty, !valid {
                    Text(strings.invalidSymbol).font(.caption).foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button(FeatureStrings.clipboard(l10n.language).cancel, role: .cancel) { dismiss() }
                Button(FeatureStrings.clipboard(l10n.language).save) {
                    save(NotchCustomShortcut(id: shortcut.id, name: name,
                                             shortcutName: shortcutName, symbol: symbol,
                                             destinations: NotchShortcutDestination.allCases.filter(destinations.contains)))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    @ObservedObject private var l10n = L10n.shared

    private func destinationTitle(_ destination: NotchShortcutDestination) -> String {
        switch destination {
        case .islandButtons: return FeatureStrings.notchEditor(l10n.language).quickActions
        case .controls: return FeatureStrings.notch(l10n.language).controls
        case .tools: return FeatureStrings.notch(l10n.language).tools
        case .shortcutsPage: return strings.title
        }
    }
}
