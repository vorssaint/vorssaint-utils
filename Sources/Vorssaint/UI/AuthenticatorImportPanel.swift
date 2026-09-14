// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The review of what an import found, in its own small window rather than
/// a sheet in Settings: a scan started from the palette should not pull the
/// person into the Settings window.
final class AuthenticatorImportPanel {
    static let shared = AuthenticatorImportPanel()

    private var panel: NSPanel?

    private init() {}

    func show(_ batch: AuthenticatorService.ImportBatch, add: @escaping ([OTPEntry]) -> Void) {
        let text = FeatureStrings.authenticator(L10n.shared.language)
        let content = ImportReview(text: text, batch: batch, add: add, close: { [weak self] in self?.hide() })
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        let panel = ensurePanel()
        panel.contentViewController = host
        panel.title = text.importTitle
        host.view.layoutSubtreeIfNeeded()
        panel.setContentSize(host.view.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
    }

    private final class ImportPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = ImportPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                                styleMask: [.titled, .closable, .utilityWindow],
                                backing: .buffered,
                                defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

/// What an import found, with duplicates unchecked, before anything is
/// added.
struct ImportReview: View {
    let text: AuthenticatorFeatureStrings
    let batch: AuthenticatorService.ImportBatch
    let add: ([OTPEntry]) -> Void
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var chosen: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: text.importFoundFormat, batch.entries.count))
                .font(.headline)
            if batch.failures > 0 {
                Text(String(format: text.importSkippedFormat, batch.failures))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(batch.entries, id: \.account.id) { entry in
                        let duplicate = batch.duplicates.contains(entry.account.id)
                        Toggle(isOn: Binding(
                            get: { chosen.contains(entry.account.id) },
                            set: { on in
                                if on { chosen.insert(entry.account.id) } else { chosen.remove(entry.account.id) }
                            })) {
                            HStack(spacing: 8) {
                                AuthenticatorInitials(name: entry.account.displayName)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.account.displayName).fontWeight(.medium)
                                    if !entry.account.secondaryName.isEmpty {
                                        Text(entry.account.secondaryName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if duplicate {
                                    Text(text.importDuplicate)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Text(OneTimePassword.grouped(
                                    OneTimePassword.code(for: entry.account, secret: entry.secret)))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320)
            HStack {
                Spacer()
                Button(l10n.s.uninstallerCancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(text.importAdd) {
                    add(batch.entries.filter { chosen.contains($0.account.id) })
                    close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear {
            chosen = Set(batch.entries.map(\.account.id)).subtracting(batch.duplicates)
        }
    }
}
