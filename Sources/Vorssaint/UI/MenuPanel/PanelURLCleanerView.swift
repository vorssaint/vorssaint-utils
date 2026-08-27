// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct PanelURLCleanerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = URLCleanerService.shared
    @AppStorage(DefaultsKey.urlCleanerEnabled) private var autoClean = false
    @State private var input = ""
    @State private var output = ""
    @State private var message: String?

    var onClose: () -> Void
    private var canClearInput: Bool { !input.isEmpty || !output.isEmpty || message != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            autoCleanToggle
            manualCleaner
        }
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(l10n.s.urlCleanerName, systemImage: "link")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }

    private var autoCleanToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(l10n.s.urlCleanerEnable, isOn: $autoClean)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))
                .onChange(of: autoClean) { _, _ in
                    URLCleanerService.shared.syncWithPreferences()
                }
            Text(l10n.s.urlCleanerEnableCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if autoClean, cleaner.isRunning {
                Label(l10n.s.urlCleanerActiveNow, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
        .panelCard()
    }

    private var manualCleaner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.s.urlCleanerManualTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                TextField(l10n.s.urlCleanerInputPlaceholder, text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button {
                    clearInput()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(canClearInput ? 1 : 0.35))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(l10n.s.urlCleanerClearButton)
                .disabled(!canClearInput)
            }
            HStack(spacing: 7) {
                Button(l10n.s.urlCleanerPasteButton) {
                    paste()
                }
                Button(l10n.s.urlCleanerCleanButton) {
                    clean()
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button(l10n.s.urlCleanerCopyButton) {
                    copy()
                }
                .disabled(output.isEmpty)
            }
            .controlSize(.small)

            resultView
        }
        .panelCard()
    }

    @ViewBuilder
    private var resultView: some View {
        if output.isEmpty {
            Text(message ?? l10n.s.urlCleanerOutputPlaceholder)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(output)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let message {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Through the shared lane: a direct read here would both race the
    /// clipboard services on AppKit's pasteboard cache and hang the button
    /// (and with it the app) on a promised flavour nobody renders any more.
    private func paste() {
        GeneralPasteboardAccess.shared.async({
            NSPasteboard.general.string(forType: .string) ?? ""
        }, then: { pasted in
            self.input = pasted
            self.clean()
        })
    }

    private func clean() {
        let result = cleaner.clean(input)
        output = result?.url ?? ""
        switch URLCleaning.outcome(for: result, input: input) {
        case .notAURL: message = l10n.s.urlCleanerNoURL
        case .unchanged: message = l10n.s.urlCleanerNoChange
        case .rewritten: message = l10n.s.urlCleanerCleaned
        case .removed(let names):
            message = String(format: l10n.s.urlCleanerRemovedFormat, names.joined(separator: ", "))
        }
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
