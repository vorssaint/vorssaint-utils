// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What Keep Awake asks of the AI Agents reader to follow whichever agent
/// works: Claude, Codex, OpenCode or Copilot.
enum KeepAwakeAgentWork {
    /// Whether anything reads the agents' logs: the AI Agents section is on
    /// and follows at least one agent.
    static func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        NotchAgentSupport.isEnabled(in: defaults) && !NotchAgentSupport.providers(in: defaults).isEmpty
    }

    /// Keep Awake is set to follow the agents and can. The usage service
    /// then keeps reading while the island is away.
    static func isWatched(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.keepAwakeAgentsWorking)
            && AppFeature.keepAwake.isAvailable(in: defaults)
            && isAvailable(in: defaults)
    }

    /// Whether the usage snapshot shows an agent at work: a turn that
    /// writes, or a Claude turn quiet behind a long shell command.
    static func isWorking(in snapshot: AgentUsageSnapshot) -> Bool {
        snapshot.claudeCommandWaiting || !snapshot.live.isEmpty
    }
}
