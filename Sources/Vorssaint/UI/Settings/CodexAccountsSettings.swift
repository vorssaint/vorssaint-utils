// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct CodexAccountsSettings: View {
    @AppStorage(DefaultsKey.notchAgentsCodexProfiles) private var saved = ""
    @ObservedObject private var service = CodexProfileLimitsService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var invalidFolder = false
    private var profiles: [CodexAccountProfile] { CodexAccountProfile.decode(saved) }
    private var text: CodexAccountStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.subheadline.weight(.medium))
            Text(text.explanation)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(profiles) { profile in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(text.accountName, text: Binding(
                            get: { profiles.first { $0.id == profile.id }?.name ?? profile.name },
                            set: { value in
                                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                var updated = profiles
                                if let index = updated.firstIndex(where: { $0.id == profile.id }) {
                                    updated[index].name = String(value.prefix(40)); save(updated)
                                }
                            }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Codex · " + text.accountName + ": " + profile.name)
                        Text(profile.directory).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .truncationMode(.middle).help(profile.directory)
                    }
                    Button { save(profiles.filter { $0.id != profile.id }) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help(text.remove)
                }
            }
            HStack {
                Button(text.find) {
                    var updated = profiles
                    for profile in CodexAccountProfile.discover() where !updated.contains(where: {
                        $0.canonicalDirectory == profile.canonicalDirectory
                    }) { updated.append(profile) }
                    save(Array(updated.prefix(8)))
                }
                Button(text.add) { addFolder() }
                    .disabled(profiles.count >= 8)
                if !profiles.isEmpty {
                    Button(text.check) { service.refresh(force: true) }
                        .disabled(service.states.contains(where: \.checking))
                }
            }
            if profiles.isEmpty {
                Text(text.fallback)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(text.resetsNote)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { service.synchronize() }
        .onChange(of: saved) { _, _ in service.synchronize() }
        .alert(text.chooseFolder, isPresented: $invalidFolder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(text.invalidFolder)
        }
    }

    private func save(_ value: [CodexAccountProfile]) {
        saved = CodexAccountProfile.encode(value)
        service.synchronize()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent == ".codex" ? "Default"
            : url.lastPathComponent.replacingOccurrences(of: ".codex-", with: "").capitalized
        let profile = CodexAccountProfile(id: UUID().uuidString, name: String(name.prefix(40)), directory: url.path)
        guard let canonical = profile.canonicalDirectory else { invalidFolder = true; return }
        guard !profiles.contains(where: { $0.canonicalDirectory == canonical }) else { return }
        save(profiles + [CodexAccountProfile(id: profile.id, name: profile.name, directory: canonical.path)])
    }
}
