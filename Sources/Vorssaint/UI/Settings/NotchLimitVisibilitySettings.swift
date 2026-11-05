// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Where each account's limits show: a switch for the island and one for
/// the lock screen, a row for every account the sections above connect.
struct NotchLimitVisibilitySettings: View {
    let claude: Bool
    let codex: Bool
    @AppStorage(DefaultsKey.notchAgentsClaudeSeats) private var seats = ""
    @AppStorage(DefaultsKey.notchAgentsCodexProfiles) private var codexProfiles = ""
    @AppStorage(DefaultsKey.notchAgentsIslandHiddenAccounts) private var islandAccounts = ""
    @AppStorage(DefaultsKey.notchAgentsLockHiddenAccounts) private var lockAccounts = ""
    @AppStorage(DefaultsKey.notchAgentsIslandHiddenProfiles) private var islandProfiles = ""
    @AppStorage(DefaultsKey.notchAgentsLockHiddenProfiles) private var lockProfiles = ""
    @AppStorage(DefaultsKey.notchAgentsClaudeBilling) private var billing = AgentClaudeBilling.automatic.rawValue
    @ObservedObject private var seatService = ClaudeSeatLimitsService.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: NotchLimitVisibilityStrings { FeatureStrings.limitVisibility(l10n.language) }

    /// One row: who it is, and its switch in each place, or a dash where
    /// that place never shows it.
    private struct Row: Identifiable {
        let id: String
        let provider: AgentProvider
        let name: String
        let detail: String
        var active = false
        let account: NotchLimitAccount
        var island = true
        var lockScreen = true
    }

    private var rows: [Row] {
        _ = billing
        var rows: [Row] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func short(_ path: String) -> String { path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path }
        if claude {
            let profiles = ClaudeSeatProfile.decode(seats)
            if profiles.isEmpty {
                rows.append(Row(id: "claude", provider: .claude, name: AgentProvider.claude.displayName,
                                detail: text.claudeDetail, account: .claude))
            }
            for profile in profiles {
                let identity = seatService.states.first { $0.id == profile.id }?.identity
                    ?? ClaudeSeatIdentity.read(profile.profileURL)
                rows.append(Row(id: profile.id, provider: .claude,
                                name: identity?.email ?? FeatureStrings.claudeSeats(l10n.language).notSignedIn,
                                detail: text.seatDetail(short(profile.directory)),
                                active: identity?.account != nil && identity?.account == seatService.activeAccount,
                                account: .profile(profile.id)))
            }
            if AgentClaudeBilling.usesAPI() {
                rows.append(Row(id: "claudeAPI", provider: .claude, name: FeatureStrings.claudeSeats(l10n.language).apiTitle,
                                detail: text.apiDetail, account: .claudeAPI))
            }
        }
        if codex {
            let homes = CodexAccountProfile.decode(codexProfiles)
            for home in homes {
                rows.append(Row(id: home.id, provider: .codex, name: home.name, detail: short(home.directory),
                                account: .profile(home.id), lockScreen: false))
            }
            // The lock screen's Codex widget reads the usual home; with homes
            // added, the island shows those instead.
            rows.append(Row(id: "codex", provider: .codex, name: AgentProvider.codex.displayName,
                            detail: text.codexDetail, account: .codex, island: homes.isEmpty))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(text.title).font(.subheadline.weight(.medium))
                Text(text.explanation)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Color.clear.frame(height: 1).gridCellUnsizedAxes([.horizontal, .vertical])
                        Text(text.island).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.center)
                        Text(text.lockScreen).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.center)
                    }
                    ForEach(rows) { row in
                        GridRow {
                            label(row)
                            toggle(row, .island, available: row.island)
                            toggle(row, .lockScreen, available: row.lockScreen)
                        }
                    }
                }
            }
        }
    }

    private func label(_ row: Row) -> some View {
        HStack(spacing: 12) {
            NotchAgentMark(provider: row.provider, size: 13)
                .frame(width: 26, height: 26)
                .background(row.provider.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if row.active {
                        Circle().fill(AgentProvider.claude.tint).frame(width: 6, height: 6)
                            .help(FeatureStrings.claudeSeats(l10n.language).activeHelp)
                    }
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                }
                Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func toggle(_ row: Row, _ place: NotchLimitPlace, available: Bool) -> some View {
        if available {
            Toggle(row.name + " · " + (place == .island ? text.island : text.lockScreen), isOn: binding(row.account, place))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        } else {
            Text("—").foregroundStyle(.tertiary).help(text.notShown).accessibilityLabel(text.notShown)
        }
    }

    private func binding(_ account: NotchLimitAccount, _ place: NotchLimitPlace) -> Binding<Bool> {
        Binding {
            _ = (islandAccounts, lockAccounts, islandProfiles, lockProfiles)
            return NotchLimitVisibility.shows(account, in: place)
        } set: { shown in
            NotchLimitVisibility.set(account, in: place, shown: shown)
            // Checks start or stop with what shows.
            ClaudeSeatLimitsService.shared.synchronize()
            CodexProfileLimitsService.shared.refresh()
            AgentUsageService.shared.syncWithPreferences()
        }
    }
}
