// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct URLCleanerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = URLCleanerService.shared
    @AppStorage(DefaultsKey.urlCleanerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.urlCleanerCustomParameters) private var customParameters = ""
    /// Typing is kept out of the stored value on purpose. `@AppStorage` writes
    /// every keystroke and the cleaner re-reads the list on its next poll, so a
    /// half-typed `source` briefly removed a `?s=` parameter from anything
    /// copied at that moment.
    @State private var customDraft = ""
    @State private var input = ""
    @State private var output = ""
    @State private var message: String?
    private var canClearInput: Bool { !input.isEmpty || !output.isEmpty || message != nil }
    /// What the draft actually parses to: lowercased, trimmed and deduplicated,
    /// which is what the cleaner will match on.
    private var draftParameters: [String] {
        URLCleaning.customParameters(from: customDraft).sorted()
    }
    /// Compared as parsed sets, so stray spacing or a trailing comma does not
    /// light the button up with nothing to save.
    private var draftDiffers: Bool {
        URLCleaning.customParameters(from: customDraft)
            != URLCleaning.customParameters(from: customParameters)
    }

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.urlCleanerEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        URLCleanerService.shared.syncWithPreferences()
                    }
                Text(l10n.s.urlCleanerEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(l10n.s.urlCleanerLocalNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if enabled, cleaner.isRunning {
                    Label(l10n.s.urlCleanerActiveNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(l10n.s.urlCleanerCustomTitle) {
                // A grouped Form turns a TextField's first argument into a
                // leading label, not a placeholder: the words sat on the left
                // while the field itself was a short strip on the right, and
                // clicking the words did nothing. An empty label puts the
                // field across the whole row, the shape the Command Bar and
                // Screenshot pages already use for a field of their own.
                HStack(spacing: 8) {
                    TextField("", text: $customDraft,
                              prompt: Text(l10n.s.urlCleanerCustomPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(l10n.s.urlCleanerCustomTitle)
                        .onSubmit { commitCustomParameters() }
                    // Return commits too, but a visible button is what says so.
                    Button(l10n.s.urlCleanerCustomSaveButton) { commitCustomParameters() }
                        .disabled(!draftDiffers)
                }
                // The names as the cleaner will see them. Duplicates, casing and
                // stray spacing all disappear here, which is the only place the
                // difference between what was typed and what was kept shows.
                if !draftParameters.isEmpty {
                    Text(draftParameters.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(l10n.s.urlCleanerCustomCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.s.urlCleanerManualTitle) {
                HStack(spacing: 8) {
                    TextField("", text: $input,
                              prompt: Text(l10n.s.urlCleanerInputPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(l10n.s.urlCleanerInputPlaceholder)
                    Button {
                        clearInput()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary.opacity(canClearInput ? 1 : 0.35))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.urlCleanerClearButton)
                    .disabled(!canClearInput)
                }
                HStack {
                    Button(l10n.s.urlCleanerPasteButton) { paste() }
                    Button(l10n.s.urlCleanerCleanButton) { clean() }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(l10n.s.urlCleanerCopyButton) { copy() }
                        .disabled(output.isEmpty)
                }
                if output.isEmpty {
                    Text(message ?? l10n.s.urlCleanerOutputPlaceholder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { customDraft = customParameters }
        // A settings restore replaces the stored list; the field has to follow
        // it rather than keep showing a draft the app no longer uses.
        .onChange(of: customParameters) { _, stored in customDraft = stored }
    }

    private func commitCustomParameters() {
        guard draftDiffers else { return }
        customParameters = draftParameters.joined(separator: ", ")
    }

    private func paste() {
        input = NSPasteboard.general.string(forType: .string) ?? ""
        clean()
    }

    private func clean() {
        guard let cleaned = cleaner.clean(input) else {
            output = ""
            message = l10n.s.urlCleanerNoURL
            return
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        output = cleaned
        message = cleaned == trimmed ? l10n.s.urlCleanerNoChange : l10n.s.urlCleanerCleaned
    }

    private func copy() {
        guard !output.isEmpty else { return }
        cleaner.copy(output)
        message = l10n.s.urlCleanerCopied
    }

    private func clearInput() {
        input = ""
        output = ""
        message = nil
    }
}
