// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ClaudeAccountSettings: View {
    @AppStorage(DefaultsKey.notchAgentsClaudeAccounts) private var saved = ""
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @State private var invalidFolder = false
    private var text: ClaudeAccountStrings { FeatureStrings.claudeAccount(l10n.language) }
    private var common: CodexAccountStrings { FeatureStrings.codexAccounts(l10n.language) }
    private var accounts: [ClaudeMonitoredAccount] {
        _ = saved
        return ClaudeMonitoredAccount.configured()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.accountsTitle).font(.subheadline.weight(.medium))
            ForEach(accounts) { account in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(account.label(defaultName: text.defaultAccount), text: Binding(
                            get: { accounts.first { $0.id == account.id }?.name ?? account.name },
                            set: { value in
                                var updated = accounts
                                if let index = updated.firstIndex(where: { $0.id == account.id }) {
                                    updated[index].name = String(value.prefix(40))
                                    save(updated)
                                }
                            }))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Claude · " + common.accountName)
                        Text(account.profile.isDefault ? text.defaultAccount : account.directory)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            .help(account.profile.isDefault ? text.defaultAccount : account.directory)
                    }
                    if let index = accounts.firstIndex(where: { $0.id == account.id }), index > 0 {
                        Button {
                            var updated = accounts
                            updated.swapAt(index, index - 1)
                            save(updated)
                        } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.plain).help(FeatureStrings.clipboard(l10n.language).moveUp)
                        .accessibilityLabel(FeatureStrings.clipboard(l10n.language).moveUp)
                    }
                    Button { save(accounts.filter { $0.id != account.id }) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help(common.remove).accessibilityLabel(common.remove)
                        .disabled(accounts.count == 1 && account.profile.isDefault)
                }
            }
            HStack {
                Button(common.find) {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    add([ClaudeAccountProfile()] + ClaudeAccountProfile.discover(home: home))
                }
                .disabled(accounts.count >= ClaudeMonitoredAccount.maximum)
                Button(common.add) { chooseFolder() }
                    .disabled(accounts.count >= ClaudeMonitoredAccount.maximum)
                Button(common.check) {
                    usage.checkClaudeAccount()
                    ClaudeProfileLimitsService.shared.refresh(force: true)
                }
                .disabled(!NotchAgentSupport.isEnabled())
            }
            Text(text.multipleExplanation).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(text.signInHelp, destination: URL(string: "https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts")!)
                .font(.caption)
        }
        .alert(text.accountsTitle, isPresented: $invalidFolder) {
            Button("OK", role: .cancel) {}
        } message: { Text(text.invalidFolder) }
    }

    private func save(_ accounts: [ClaudeMonitoredAccount]) {
        let value = accounts.isEmpty ? [ClaudeMonitoredAccount(directory: "")] : accounts
        saved = ClaudeMonitoredAccount.encode(value)
        UserDefaults.standard.set(value[0].directory, forKey: DefaultsKey.notchAgentsClaudeProfile)
        NotchService.shared.syncWithPreferences()
    }

    private func add(_ profiles: [ClaudeAccountProfile]) {
        let additions = profiles.map { ClaudeMonitoredAccount(directory: $0.directory) }
        save(ClaudeMonitoredAccount.decode(ClaudeMonitoredAccount.encode(accounts + additions)))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        panel.directoryURL = home
        guard panel.runModal() == .OK else { return }
        var profiles: [ClaudeAccountProfile] = []
        for folder in panel.urls {
            let profile = ClaudeAccountProfile(directory: folder.path)
            if folder.standardizedFileURL == home.appending(path: ".claude", directoryHint: .isDirectory).standardizedFileURL,
               !FileManager.default.fileExists(atPath: profile.profileURL(home: home).path) {
                profiles.append(ClaudeAccountProfile())
            } else if profile.isAvailable(home: home) {
                profiles.append(profile)
            } else { invalidFolder = true }
        }
        add(profiles)
    }
}
