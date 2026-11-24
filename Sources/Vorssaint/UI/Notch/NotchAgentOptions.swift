// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Everything about the AI agents that can be changed without leaving the AI
/// page: which agents the island follows, whether the Mac stays awake while
/// one works, what the closed island reads out, and its alerts. The same
/// preferences Settings shows, written the same way.
struct NotchAgentOptionsMenu: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usage = AgentUsageService.shared
    /// Read so the checkmarks follow a change made here or in Settings.
    @AppStorage(DefaultsKey.keepAwakeAgentsWorking) private var keepAwake = false
    @AppStorage(DefaultsKey.keepAwakeAgentsGrace) private var grace = 5
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsFinishAlert) private var finishAlert = false
    @AppStorage(DefaultsKey.notchAgentsLimitAlert) private var limitAlert = false
    @State private var refresh = 0

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var awakeText: KeepAwakeAutomationStrings { FeatureStrings.keepAwakeAutomation(l10n.language) }

    var body: some View {
        _ = (keepAwake, grace, readout, display, finishAlert, limitAlert, refresh)
        return NotchMenuButton(title: text.title, items: items, cornerRadius: 9) {
            NotchBandMenuLabel(title: text.title, symbol: "slider.horizontal.3")
        }
    }

    private var items: [NotchMenuItem] {
        let defaults = UserDefaults.standard
        let following = AgentProvider.allCases.filter { defaults.object(forKey: NotchAgentSupport.key(for: $0)) as? Bool ?? true }
        var list: [NotchMenuItem] = AgentProvider.allCases.map { provider in
            let on = following.contains(provider)
            return NotchMenuItem(title: provider.displayName, checked: on, symbol: provider.symbol,
                                 // One agent stays on; turning the section off stops all.
                                 enabled: !(on && following.count <= 1)) {
                defaults.set(!on, forKey: NotchAgentSupport.key(for: provider))
                changed()
            }
        }
        list.append(.separator)
        list.append(NotchMenuItem(title: awakeText.agentsActive, checked: keepAwake, symbol: "bolt.fill") {
            defaults.set(!keepAwake, forKey: DefaultsKey.keepAwakeAgentsWorking)
            KeepAwakeManager.shared.automationPreferencesDidChange()
            changed()
        })
        if keepAwake {
            let steps = Defaults.allowedKeepAwakeAgentsGraceMinutes
            let next = steps[((steps.firstIndex(of: grace) ?? 0) + 1) % steps.count]
            list.append(NotchMenuItem(title: awakeText.agentsGraceTitle + ": "
                                        + KeepAwakeMouseJiggleIntervalPicker.label(for: grace),
                                      symbol: "timer") {
                defaults.set(next, forKey: DefaultsKey.keepAwakeAgentsGrace)
                KeepAwakeManager.shared.automationPreferencesDidChange()
                changed()
            })
        }
        list.append(.separator)
        for option in NotchAgentReadout.allCases {
            list.append(NotchMenuItem(title: text.readout + ": " + text.readout(option), checked: readout == option.rawValue) {
                defaults.set(option.rawValue, forKey: DefaultsKey.notchAgentsReadout)
                changed()
            })
        }
        for option in NotchAgentLimitDisplay.allCases {
            list.append(NotchMenuItem(title: text.limitsAs + ": " + (option == .used ? text.used : text.remaining),
                                      checked: display == option.rawValue) {
                defaults.set(option.rawValue, forKey: DefaultsKey.notchAgentsLimitDisplay)
                changed()
            })
        }
        list.append(.separator)
        list.append(NotchMenuItem(title: text.finishAlert, checked: finishAlert, symbol: "bell") {
            defaults.set(!finishAlert, forKey: DefaultsKey.notchAgentsFinishAlert)
            changed()
        })
        list.append(NotchMenuItem(title: text.limitAlert, checked: limitAlert, symbol: "gauge.with.dots.needle.67percent") {
            defaults.set(!limitAlert, forKey: DefaultsKey.notchAgentsLimitAlert)
            changed()
        })
        return list
    }

    private func changed() {
        refresh += 1
        NotchService.shared.syncWithPreferences()
    }
}
