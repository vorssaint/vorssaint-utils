// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct URLCleanerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = URLCleanerService.shared
    @AppStorage(DefaultsKey.urlCleanerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.urlCleanerCustomParameters) private var customParameters = ""
    @State private var input = ""
    @State private var output = ""
    @State private var message: String?
    private var canClearInput: Bool { !input.isEmpty || !output.isEmpty || message != nil }

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
                TextField(l10n.s.urlCleanerCustomPlaceholder, text: $customParameters)
                Text(l10n.s.urlCleanerCustomCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.s.urlCleanerManualTitle) {
                HStack(spacing: 8) {
                    TextField(l10n.s.urlCleanerInputPlaceholder, text: $input)
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
