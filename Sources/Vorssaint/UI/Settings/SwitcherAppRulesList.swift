// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SwitcherAppRulesList: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var rules: [String: SwitcherAppRule] = Self.savedRules

    private var text: SwitcherAppRulesStrings {
        FeatureStrings.switcherAppRules(l10n.language)
    }

    var body: some View {
        AppBundleList(title: text.listTitle,
                      caption: text.caption,
                      addTitle: text.addButton,
                      removeLabel: text.removeButton,
                      bundleIDs: Array(rules.keys),
                      reachesEveryApp: true,
                      onAdd: { bundleID in
                          var updated = rules
                          updated[bundleID] = .showWithoutWindows
                          save(updated)
                      },
                      onRemove: { bundleID in
                          var updated = rules
                          updated.removeValue(forKey: bundleID)
                          save(updated)
                      }) { bundleID in
            Picker(text.behaviorLabel, selection: binding(for: bundleID)) {
                Text(text.showWithoutWindows).tag(SwitcherAppRule.showWithoutWindows)
                Text(text.windowsOnly).tag(SwitcherAppRule.windowsOnly)
                Text(text.hidden).tag(SwitcherAppRule.hidden)
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private static var savedRules: [String: SwitcherAppRule] {
        SwitcherAppRule.rules(
            storedValue: UserDefaults.standard.dictionary(forKey: DefaultsKey.switcherAppRules))
    }

    private func binding(for bundleID: String) -> Binding<SwitcherAppRule> {
        Binding(
            get: { rules[bundleID] ?? .windowsOnly },
            set: { newRule in
                var updated = rules
                updated[bundleID] = newRule
                save(updated)
            }
        )
    }

    private func save(_ updated: [String: SwitcherAppRule]) {
        let stored = SwitcherAppRule.storedValue(updated)
        UserDefaults.standard.set(stored, forKey: DefaultsKey.switcherAppRules)
        rules = SwitcherAppRule.rules(storedValue: stored as [String: Any])
    }
}
