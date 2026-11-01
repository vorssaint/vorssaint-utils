// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where an account's limits can show.
enum NotchLimitPlace: CaseIterable {
    /// The AI page and the resting island.
    case island
    case lockScreen

    fileprivate var accountsKey: String {
        self == .island ? DefaultsKey.notchAgentsIslandHiddenAccounts : DefaultsKey.notchAgentsLockHiddenAccounts
    }

    fileprivate var profilesKey: String {
        self == .island ? DefaultsKey.notchAgentsIslandHiddenProfiles : DefaultsKey.notchAgentsLockHiddenProfiles
    }
}

/// An account that reports limits: the usual Claude account, the API key
/// that pays for Claude Code elsewhere, Codex's usual home, or a Claude seat
/// or added Codex home by its profile's id.
enum NotchLimitAccount: Hashable {
    case claude, claudeAPI, codex
    case profile(String)

    fileprivate var name: String? {
        switch self {
        case .claude: return "claude"
        case .claudeAPI: return "claudeAPI"
        case .codex: return "codex"
        case .profile: return nil
        }
    }
}

/// Which accounts each place leaves out. Everything shows until the person
/// turns an account off; one shown nowhere is not checked at all.
enum NotchLimitVisibility {
    static func shows(_ account: NotchLimitAccount, in place: NotchLimitPlace,
                      defaults: UserDefaults = .standard) -> Bool {
        switch account {
        case .profile(let id): return !hidden(place.profilesKey, defaults).contains(id)
        default: return !hidden(place.accountsKey, defaults).contains(account.name ?? "")
        }
    }

    /// Shown in at least one place, so worth checking.
    static func isChecked(_ account: NotchLimitAccount, defaults: UserDefaults = .standard) -> Bool {
        NotchLimitPlace.allCases.contains { shows(account, in: $0, defaults: defaults) }
    }

    static func set(_ account: NotchLimitAccount, in place: NotchLimitPlace, shown: Bool,
                    defaults: UserDefaults = .standard) {
        let key: String, value: String
        switch account {
        case .profile(let id): (key, value) = (place.profilesKey, id)
        default: (key, value) = (place.accountsKey, account.name ?? "")
        }
        var list = defaults.string(forKey: key).map(parse) ?? []
        list.removeAll { $0 == value }
        if !shown { list.append(value) }
        defaults.set(list.joined(separator: ","), forKey: key)
    }

    /// The seats a place shows, in the person's order.
    static func seats(_ snapshot: AgentUsageSnapshot, in place: NotchLimitPlace,
                      defaults: UserDefaults = .standard) -> [ClaudeSeat] {
        let left = hidden(place.profilesKey, defaults)
        return snapshot.claudeSeats.filter { !left.contains($0.id) }
    }

    /// The snapshot as a place sees it: hidden seats gone, Claude's one
    /// reading the visible active seat's, and a hidden account's limits
    /// dropped. Only limits change; usage and sessions stay.
    static func applying(_ snapshot: AgentUsageSnapshot, in place: NotchLimitPlace,
                         defaults: UserDefaults = .standard) -> AgentUsageSnapshot {
        var shown = snapshot
        if !snapshot.claudeSeats.isEmpty {
            shown.claudeSeats = seats(snapshot, in: place, defaults: defaults)
            shown.limits[.claude] = shown.claudeSeats.isEmpty ? nil : shown.activeClaudeSeat?.limits
        } else if !shows(.claude, in: place, defaults: defaults) {
            shown.limits[.claude] = nil
        }
        if !shows(.codex, in: place, defaults: defaults) { shown.limits[.codex] = nil }
        return shown
    }

    private static func hidden(_ key: String, _ defaults: UserDefaults) -> Set<String> {
        Set(defaults.string(forKey: key).map(parse) ?? [])
    }

    private static func parse(_ value: String) -> [String] {
        value.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
}

extension NotchLockScreenWidgets {
    /// The lock screen's widgets less Claude's and Codex's when the person
    /// turned off every account they would show, so the rail closes up as
    /// if they were hidden here.
    func leavingOutHiddenLimits(_ defaults: UserDefaults = .standard) -> Self {
        var result = self
        let seats = ClaudeSeatProfile.decode(defaults.string(forKey: DefaultsKey.notchAgentsClaudeSeats) ?? "")
        let claude = seats.isEmpty
            ? NotchLimitVisibility.shows(.claude, in: .lockScreen, defaults: defaults)
            : seats.contains { NotchLimitVisibility.shows(.profile($0.id), in: .lockScreen, defaults: defaults) }
        if !claude { result.hidden.insert(.claude) }
        if !NotchLimitVisibility.shows(.codex, in: .lockScreen, defaults: defaults) { result.hidden.insert(.codex) }
        return result
    }
}
