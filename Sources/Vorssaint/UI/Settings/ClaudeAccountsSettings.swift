// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ClaudeAccountsSettings: View {
    @AppStorage(DefaultsKey.notchAgentsClaudeProfiles) private var saved = ""
    @ObservedObject private var service = ClaudeProfileLimitsService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var invalidFolder = false
    private var profiles: [ClaudeAccountProfile] { ClaudeAccountProfile.decode(saved) }
    private var russian: Bool { l10n.language == .ru }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(russian ? "Аккаунты Claude" : "Claude accounts").font(.subheadline.weight(.medium))
            Text(russian
                 ? "Каждый аккаунт получает отдельную карточку лимитов. Claude Code проверяет выбранные профили раз в пять минут, пока раздел открыт. Запросы к моделям не отправляются."
                 : "Each account gets its own limits card. Claude Code checks the selected profiles every five minutes while the AI page is open. No model prompts are sent.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(profiles) { profile in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(russian ? "Название аккаунта" : "Account name", text: Binding(
                            get: { profiles.first { $0.id == profile.id }?.name ?? profile.name },
                            set: { value in
                                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                var updated = profiles
                                if let index = updated.firstIndex(where: { $0.id == profile.id }) {
                                    updated[index].name = String(value.prefix(40)); save(updated)
                                }
                            }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Claude account name: " + profile.name)
                        Text(profile.directory).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .truncationMode(.middle).help(profile.directory)
                    }
                    Button {
                        save(profiles.filter { $0.id != profile.id })
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain).help(russian ? "Убрать карточку аккаунта" : "Remove this account’s card")
                }
            }
            HStack {
                Button(russian ? "Найти локальные аккаунты" : "Find local accounts") {
                    var updated = profiles
                    for profile in ClaudeAccountProfile.discover() where !updated.contains(where: {
                        $0.canonicalDirectory == profile.canonicalDirectory
                    }) { updated.append(profile) }
                    save(Array(updated.prefix(8)))
                }
                Button(russian ? "Добавить папку…" : "Add folder…") { addFolder() }
                    .disabled(profiles.count >= 8)
                if !profiles.isEmpty {
                    Button(russian ? "Проверить лимиты" : "Check limits") { service.refresh(force: true) }
                        .disabled(service.states.contains(where: \.checking))
                }
            }
            if profiles.isEmpty {
                Text(russian ? "Без выбранных профилей используется история приложения Claude." : "With no accounts selected, the Claude desktop app remains the source of limits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { service.synchronize() }
        .alert(russian ? "Выбери папку профиля Claude Code" : "Choose a Claude Code profile folder", isPresented: $invalidFolder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(russian ? "В ней должен находиться файл .claude.json. Файлы входа не изменяются."
                 : "The folder must contain .claude.json. Sign-in files are never changed.")
        }
    }

    private func save(_ value: [ClaudeAccountProfile]) {
        saved = ClaudeAccountProfile.encode(value)
        service.synchronize()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let profile = ClaudeAccountProfile(id: UUID().uuidString,
            name: url.lastPathComponent.replacingOccurrences(of: ".claude-", with: "").capitalized, directory: url.path)
        guard let canonical = profile.canonicalDirectory else { invalidFolder = true; return }
        guard !profiles.contains(where: { $0.canonicalDirectory == canonical }) else { return }
        save(profiles + [profile])
    }
}
