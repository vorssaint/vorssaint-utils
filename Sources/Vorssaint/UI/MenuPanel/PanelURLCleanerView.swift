// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct PanelURLCleanerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = URLCleanerService.shared
    @AppStorage(DefaultsKey.urlCleanerEnabled) private var autoClean = false
    // The service reads the rules itself. `result` reads them too, so a rule
    // changed in Settings while the panel sits beside it redraws the result.
    @AppStorage(DefaultsKey.urlCleanerCustomParameters) private var globalNames = ""
    @AppStorage(DefaultsKey.urlCleanerSiteParameters) private var siteNames = ""
    @AppStorage(DefaultsKey.urlCleanerDisabledParameters) private var disabledNames = ""
    @State private var input = ""
    @State private var copied: String?

    var onClose: () -> Void
    /// Worked out from the field on every render, so Copy always takes the
    /// link that is in the field now under the rules in force now.
    private var result: URLCleaning.Result? {
        _ = (globalNames, siteNames, disabledNames)
        return cleaner.clean(input)
    }

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
                        .foregroundStyle(Color.secondary.opacity(input.isEmpty ? 0.35 : 1))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(l10n.s.urlCleanerClearButton)
                .disabled(input.isEmpty)
            }
            HStack(spacing: 7) {
                Button(l10n.s.urlCleanerPasteButton) {
                    paste()
                }
                Spacer()
                Button(l10n.s.urlCleanerCopyButton) {
                    copy()
                }
                .buttonStyle(.borderedProminent)
                .disabled(result == nil)
            }
            .controlSize(.small)

            resultView
        }
        .panelCard()
    }

    @ViewBuilder
    private var resultView: some View {
        if let output = result?.url {
            VStack(alignment: .leading, spacing: 5) {
                Text(output)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(input.isEmpty ? l10n.s.urlCleanerOutputPlaceholder : message)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }

    private var message: String {
        if let copied, copied == result?.url { return l10n.s.urlCleanerCopied }
        switch URLCleaning.outcome(for: result, input: input) {
        case .notAURL: return l10n.s.urlCleanerNoURL
        case .unchanged: return l10n.s.urlCleanerNoChange
        case .rewritten: return l10n.s.urlCleanerCleaned
        case .removed(let names):
            return String(format: l10n.s.urlCleanerRemovedFormat, names.joined(separator: ", "))
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
        })
    }

    private func copy() {
        guard let url = result?.url else { return }
        cleaner.copy(url)
        copied = url
    }

    private func clearInput() {
        input = ""
        copied = nil
    }
}
