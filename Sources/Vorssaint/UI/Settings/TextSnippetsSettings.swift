// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The text snippets page: the enable toggle, the snippet list and a simple
/// editor sheet. Edits persist to defaults and nudge the service, so a change
/// works on the very next keystroke.
struct TextSnippetsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.textSnippetsEnabled) private var enabled = false
    @State private var snippets: [TextSnippet] = TextSnippetSupport.decode(
        UserDefaults.standard.data(forKey: DefaultsKey.textSnippets))
    @State private var editing: TextSnippet?
    @State private var creating = false

    private var text: SnippetFeatureStrings {
        FeatureStrings.snippets(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        TextSnippetService.shared.syncWithPreferences()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            }

            Section {
                if snippets.isEmpty {
                    Text(text.emptyList)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(snippets) { snippet in
                    SnippetRow(snippet: snippet,
                               modeLabel: snippet.expansion == .immediate
                                   ? text.expansionImmediate
                                   : text.expansionDelimiter,
                               toggle: { setEnabled($0, id: snippet.id) },
                               edit: { editing = snippet })
                }
                Button {
                    creating = true
                } label: {
                    Label(text.addButton, systemImage: "plus")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.variablesHint)
                    Text(text.variablesCaption)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $creating) {
            SnippetEditor(text: text,
                          snippet: TextSnippet(),
                          isNew: true,
                          others: snippets,
                          save: { upsert($0) },
                          delete: nil)
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(text: text,
                          snippet: snippet,
                          isNew: false,
                          others: snippets.filter { $0.id != snippet.id },
                          save: { upsert($0) },
                          delete: { remove(id: snippet.id) })
        }
    }

    private func upsert(_ snippet: TextSnippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        persist()
    }

    private func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }

    private func setEnabled(_ on: Bool, id: UUID) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[index].enabled = on
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(TextSnippetSupport.encode(snippets),
                                  forKey: DefaultsKey.textSnippets)
        TextSnippetService.shared.syncWithPreferences()
    }
}

private struct SnippetRow: View {
    let snippet: TextSnippet
    let modeLabel: String
    let toggle: (Bool) -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(snippet.name.isEmpty ? snippet.trigger : snippet.name)
                            .fontWeight(.medium)
                        Text(snippet.trigger)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            )
                    }
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text(modeLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Toggle("", isOn: Binding(get: { snippet.enabled }, set: toggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 1)
    }

    private var preview: String {
        snippet.replacement.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct SnippetEditor: View {
    let text: SnippetFeatureStrings
    @State var snippet: TextSnippet
    let isNew: Bool
    let others: [TextSnippet]
    let save: (TextSnippet) -> Void
    let delete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    private var sanitizedTrigger: String {
        TextSnippetSupport.sanitizedTrigger(snippet.trigger)
    }

    private var triggerTooShort: Bool {
        sanitizedTrigger.count < 2
    }

    private var duplicateTrigger: Bool {
        others.contains { $0.trigger == sanitizedTrigger }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? text.newTitle : text.editTitle)
                .font(.headline)
            Form {
                TextField(text.nameLabel, text: $snippet.name, prompt: Text(text.namePlaceholder))
                TextField(text.triggerLabel, text: $snippet.trigger, prompt: Text(text.triggerPlaceholder))
                    .font(.body.monospaced())
                Picker(text.expansionLabel, selection: $snippet.expansion) {
                    Text(text.expansionDelimiter).tag(TextSnippet.Expansion.afterDelimiter)
                    Text(text.expansionImmediate).tag(TextSnippet.Expansion.immediate)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.replacementLabel)
                    TextEditor(text: $snippet.replacement)
                        .font(.body)
                        .frame(minHeight: 76)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                    Text(text.variablesHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)
            if triggerTooShort, !snippet.trigger.isEmpty {
                Text(text.triggerTooShort)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if duplicateTrigger {
                Text(text.duplicateTrigger)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                if let delete {
                    Button(role: .destructive) {
                        delete()
                        dismiss()
                    } label: {
                        Text(text.deleteButton)
                    }
                }
                Spacer()
                Button(l10n.s.uninstallerCancel) { dismiss() }
                Button(text.saveButton) {
                    var saved = snippet
                    saved.trigger = sanitizedTrigger
                    saved.name = snippet.name.trimmingCharacters(in: .whitespaces)
                    save(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(triggerTooShort || duplicateTrigger || snippet.replacement.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}
