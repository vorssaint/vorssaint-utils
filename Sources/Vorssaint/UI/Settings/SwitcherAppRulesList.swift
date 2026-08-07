// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SwitcherAppRulesList: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var rules: [String: SwitcherAppRule]
    @State private var isExpanded: Bool
    @State private var showingAppPicker = false

    init() {
        let rules = Self.savedRules
        _rules = State(initialValue: rules)
        _isExpanded = State(initialValue: !rules.isEmpty)
    }

    private var text: SwitcherAppRulesStrings {
        FeatureStrings.switcherAppRules(l10n.language)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(sortedBundleIDs, id: \.self) { bundleID in
                HStack(spacing: 9) {
                    Image(nsImage: InstalledApps.icon(for: bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(InstalledApps.name(for: bundleID))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Picker(text.behaviorLabel, selection: binding(for: bundleID)) {
                        Text(text.showWithoutWindows).tag(SwitcherAppRule.showWithoutWindows)
                        Text(text.windowsOnly).tag(SwitcherAppRule.windowsOnly)
                        Text(text.hidden).tag(SwitcherAppRule.hidden)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Button {
                        var updated = rules
                        updated.removeValue(forKey: bundleID)
                        save(updated)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text.removeButton)
                }
            }

            Button {
                showingAppPicker = true
            } label: {
                Label(text.addButton, systemImage: "plus")
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(text.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(text.listTitle)
                Spacer()
                if !rules.isEmpty {
                    Text("\(rules.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private static var savedRules: [String: SwitcherAppRule] {
        SwitcherAppRule.rules(
            storedValue: UserDefaults.standard.dictionary(forKey: DefaultsKey.switcherAppRules))
    }

    private var sortedBundleIDs: [String] {
        rules.keys.sorted {
            InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let listed = Set(rules.keys)
        return AppPickerView(canBrowseApplications: true) {
            showingAppPicker = false
        } onSelect: { url in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            var updated = rules
            updated[bundleID] = .showWithoutWindows
            save(updated)
            showingAppPicker = false
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: listed,
                                                       includeRunningApplications: true)
        }
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
